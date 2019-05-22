/*PGR-MIT*****************************************************************

=========================
pgRouting Graph Analytics
=========================
:Author: Stephen Woodbridge <woodbri@swoodbridge.com>
:Date: $Date: 2013-03-22 20:14:00 -5000 (Fri, 22 Mar 2013) $
:Revision: $Revision: 0000 $
:Description: This is a collection of tools for analyzing graphs.
It has been contributed to pgRouting by iMaptools.com.
:Copyright: Stephen Woodbridge. This is released under the MIT-X license.

------
MIT/X license

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:


The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.


THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

********************************************************************PGR-MIT*/


/*
.. function:: _pgr_analyzeOneway(tab, col, s_in_rules, s_out_rules, t_in_rules, t_out_rules)

   This function analyzes oneway streets in a graph and identifies any
   flipped segments. Basically if you count the edges coming into a node
   and the edges exiting a node the number has to be greater than one.

   * tab              - edge table name (TEXT)
   * col              - oneway column name (TEXT)
   * s_in_rules       - source node in rules
   * s_out_rules      - source node out rules
   * t_in_tules       - target node in rules
   * t_out_rules      - target node out rules
   * two_way_if_null  - flag to treat oneway NULL values as by directional

   After running this on a graph you can identify nodes with potential
   problems with the following query.

.. code-block:: sql

       SELECT * FROM vertices_tmp WHERE in=0 OR out=0;

   The rules are defined as an array of text strings that if match the "col"
   value would be counted as true for the source or target in or out condition.

   Example
   =======

   Lets assume we have a table "st" of edges and a column "one_way" that
   might have values like:

   * 'FT'    - oneway from the source to the target node.
   * 'TF'    - oneway from the target to the source node.
   * 'B'     - two way street.
   * ''      - empty field, assume teoway.
   * <NULL>  - NULL field, use two_way_if_null flag.

   Then we could form the following query to analyze the oneway streets for
   errors.

.. code-block:: sql

   SELECT _pgr_analyzeOneway('st', 'one_way',
        ARRAY['', 'B', 'TF'],
        ARRAY['', 'B', 'FT'],
        ARRAY['', 'B', 'FT'],
        ARRAY['', 'B', 'TF'],
        true);

   -- now we can see the problem nodes
   SELECT * FROM vertices_tmp WHERE ein=0 OR eout=0;

   -- and the problem edges connected to those nodes
   SELECT gid

     FROM st a, vertices_tmp b
    WHERE a.source=b.id AND ein=0 OR eout=0
   union
   SELECT gid
     FROM st a, vertices_tmp b
    WHERE a.target=b.id AND ein=0 OR eout=0;

Typically these problems are generated by a break in the network, the
oneway direction set wrong, maybe an error releted to zlevels or
a network that is not properly noded.

*/

CREATE OR REPLACE FUNCTION pgr_analyzeOneway(
   TEXT,
   TEXT[], -- s_in_rules (required)
   TEXT[], -- s_out_rules (required)
   TEXT[], -- t_in_rules (required)
   TEXT[], -- t_out_rules (required)

   two_way_if_null BOOLEAN default true,
   oneway TEXT default 'oneway',
   source TEXT default 'source',
   target TEXT default 'target')
  RETURNS TEXT AS
$BODY$


DECLARE
    edge_table TEXT := $1;
    s_in_rules TEXT[] := $2;
    s_out_rules TEXT[] := $3;
    t_in_rules TEXT[] := $4;
    t_out_rules TEXT[] := $5;
    rule TEXT;
    ecnt INTEGER;
    instr TEXT;
    naming record;
    sname TEXT;
    tname TEXT;
    tabname TEXT;
    vname TEXT;
    owname TEXT;
    sourcename TEXT;
    targetname TEXT;
    sourcetype TEXT;
    targettype TEXT;
    vertname TEXT;
    debuglevel TEXT;


BEGIN
  RAISE notice 'PROCESSING:';
  RAISE notice 'pgr_analyzeOneway(''%'',''%'',''%'',''%'',''%'',''%'',''%'',''%'',%)',
		edge_table, s_in_rules , s_out_rules, t_in_rules, t_out_rules, oneway, source ,target,two_way_if_null ;
  execute 'show client_min_messages' into debuglevel;

  BEGIN
    RAISE DEBUG 'Checking % exists',edge_table;
    execute 'SELECT * FROM _pgr_getTableName('||quote_literal(edge_table)||',2)' into naming;
    sname=naming.sname;
    tname=naming.tname;
    tabname=sname||'.'||tname;
    vname=tname||'_vertices_pgr';
    vertname= sname||'.'||vname;
    RAISE DEBUG '     --> OK';
    EXCEPTION WHEN raise_exception THEN
      RAISE NOTICE 'ERROR: something went wrong checking the table name';
      RETURN 'FAIL';
  END;

  BEGIN
       RAISE debug 'Checking Vertices table';
       execute 'SELECT * FROM  _pgr_checkVertTab('||quote_literal(vertname) ||', ''{"id","ein","eout"}''::TEXT[])' into naming;
       execute 'UPDATE '||_pgr_quote_ident(vertname)||' SET eout=0 ,ein=0';
       RAISE DEBUG '     --> OK';
       EXCEPTION WHEN raise_exception THEN
          RAISE NOTICE 'ERROR: something went wrong checking the vertices table';
          RETURN 'FAIL';
  END;


  BEGIN
       RAISE debug 'Checking column names in edge table';
       SELECT * into sourcename FROM _pgr_getColumnName(sname, tname,source,2);
       SELECT * into targetname FROM _pgr_getColumnName(sname, tname,target,2);
       SELECT * into owname FROM _pgr_getColumnName(sname, tname,oneway,2);


       perform _pgr_onError( sourcename IN (targetname,owname) or  targetname=owname, 2,
                       '_pgr_createToplogy',  'Two columns share the same name', 'Parameter names for oneway,source and target  must be different',
                       'Column names are OK');

       RAISE DEBUG '     --> OK';
       EXCEPTION WHEN raise_exception THEN
          RAISE NOTICE 'ERROR: something went wrong checking the column names';
          RETURN 'FAIL';
  END;

  BEGIN
       RAISE debug 'Checking column types in edge table';
       SELECT * into sourcetype FROM _pgr_getColumnType(sname,tname,sourcename,1);
       SELECT * into targettype FROM _pgr_getColumnType(sname,tname,targetname,1);


       perform _pgr_onError(sourcetype NOT IN('integer','smallint','bigint') , 2,
                       '_pgr_createTopology',  'Wrong type of Column '|| sourcename, ' Expected type of '|| sourcename || ' is INTEGER,smallint OR BIGINT but '||sourcetype||' was found',
                       'Type of Column '|| sourcename || ' is ' || sourcetype);

       perform _pgr_onError(targettype NOT IN('integer','smallint','bigint') , 2,
                       '_pgr_createTopology',  'Wrong type of Column '|| targetname, ' Expected type of '|| targetname || ' is INTEGER,smallint OR BIGINTi but '||targettype||' was found',
                       'Type of Column '|| targetname || ' is ' || targettype);

       RAISE DEBUG '     --> OK';
       EXCEPTION WHEN raise_exception THEN
          RAISE NOTICE 'ERROR: something went wrong checking the column types';
          RETURN 'FAIL';
   END;



    RAISE NOTICE 'Analyzing graph for one way street errors.';

    rule := CASE WHEN two_way_if_null
            THEN owname || ' IS NULL OR '
            ELSE '' END;

    instr := '''' || array_to_string(s_in_rules, ''',''') || '''';
       EXECUTE 'UPDATE '||_pgr_quote_ident(vertname)||' a set ein=coalesce(ein,0)+b.cnt
      FROM (
         SELECT '|| sourcename ||', count(*) AS cnt
           FROM '|| tabname ||'
          WHERE '|| rule || owname ||' IN ('|| instr ||')
          GROUP BY '|| sourcename ||' ) b
     WHERE a.id=b.'|| sourcename;

    RAISE NOTICE 'Analysis 25%% complete ...';

    instr := '''' || array_to_string(t_in_rules, ''',''') || '''';
    EXECUTE 'UPDATE '||_pgr_quote_ident(vertname)||' a set ein=coalesce(ein,0)+b.cnt
        FROM (
         SELECT '|| targetname ||', count(*) AS cnt
           FROM '|| tabname ||'
          WHERE '|| rule || owname ||' IN ('|| instr ||')
          GROUP BY '|| targetname ||' ) b
        WHERE a.id=b.'|| targetname;

    RAISE NOTICE 'Analysis 50%% complete ...';

    instr := '''' || array_to_string(s_out_rules, ''',''') || '''';
    EXECUTE 'UPDATE '||_pgr_quote_ident(vertname)||' a set eout=coalesce(eout,0)+b.cnt
        FROM (
         SELECT '|| sourcename ||', count(*) AS cnt
           FROM '|| tabname ||'
          WHERE '|| rule || owname ||' IN ('|| instr ||')
          GROUP BY '|| sourcename ||' ) b
        WHERE a.id=b.'|| sourcename;
    RAISE NOTICE 'Analysis 75%% complete ...';

    instr := '''' || array_to_string(t_out_rules, ''',''') || '''';
    EXECUTE 'UPDATE '||_pgr_quote_ident(vertname)||' a set eout=coalesce(eout,0)+b.cnt
        FROM (
         SELECT '|| targetname ||', count(*) AS cnt
           FROM '|| tabname ||'
          WHERE '|| rule || owname ||' IN ('|| instr ||')
          GROUP BY '|| targetname ||' ) b
        WHERE a.id=b.'|| targetname;

    RAISE NOTICE 'Analysis 100%% complete ...';

    EXECUTE 'SELECT count(*)  FROM '||_pgr_quote_ident(vertname)||' WHERE ein=0 OR eout=0' INTO ecnt;

    RAISE NOTICE 'Found % potential problems IN directionality' ,ecnt;

    RETURN 'OK';

END;
$BODY$
  LANGUAGE plpgsql VOLATILE STRICT;

-- COMMENTS

COMMENT ON FUNCTION pgr_analyzeOneWay(TEXT,TEXT[],TEXT[], TEXT[],TEXT[],BOOLEAN,TEXT,TEXT,TEXT)
IS 'pgr_analyzeOneWay
- Parameters
  - edge table
  - source in rules
  - source out rules,
  - target in rules
  - target out rules,
- Optional parameters
  - two_way_if_null := true
  - oneway := ''oneway'',
  - source := ''source''
  - target:=''target''
- Documentation:
  - ${PGROUTING_DOC_LINK}/pgr_analyzeOneWay.html
';
