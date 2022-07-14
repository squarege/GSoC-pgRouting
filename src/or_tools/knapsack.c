/*PGR-GNU*****************************************************************
File: knapsack.c
TODO fix license
Copyright (c) 2022 pgRouting developers
Mail: project@pgrouting.org
Function's developer:
Copyright (c) 2022 Manas Sivakumar
------
This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.
This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.
You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
 ********************************************************************PGR-GNU*/

#include "c_common/postgres_connection.h"
#include "c_common/debug_macro.h"
#include "c_common/e_report.h"
#include "c_common/time_msg.h"


#include "drivers/or_tools/knapsack_driver.h"

PGDLLEXPORT Datum
_vrp_knapsack(PG_FUNCTION_ARGS);
PG_FUNCTION_INFO_V1(_vrp_knapsack);


static
void
process(
        char* weights_cost_sql,
        int capacity,
        
        Knapsack_rt **result_tuples,
        size_t *result_count) {

    pgr_SPI_connect();

    Knapsack_rt *knapsack_items = NULL;
    size_t total_knapsack_items = 0;
    get_weights_cost(weights_cost_sql,
           &knapsack_items, &total_knapsack_items);

    if (total_knapsack_items == 0) {
        (*result_count) = 0;
        (*result_tuples) = NULL;

        /* freeing memory before return */
        if (knapsack_items) {pfree(knapsack_items); knapsack_items = NULL;}

        pgr_SPI_finish();
        ereport(ERROR,
                (errcode(ERRCODE_INTERNAL_ERROR),
                 errmsg("No orders found")));
        return;
    }
    
    clock_t start_t = clock();
    char *log_msg = NULL;
    char *notice_msg = NULL;
    char *err_msg = NULL;

    do_knapsack(
            knapsack_items, total_knapsack_items,
            
            capacity,

            result_tuples,
            result_count,

            &log_msg,
            &notice_msg,
            &err_msg);

    time_msg("pgr_pickDeliver", start_t, clock());

    if (err_msg && (*result_tuples)) {
        pfree(*result_tuples);
        (*result_count) = 0;
        (*result_tuples) = NULL;
    }
    pgr_global_report(log_msg, notice_msg, err_msg);

    /* freeing memory before return */
    if (log_msg) {pfree(log_msg); log_msg = NULL;}
    if (notice_msg) {pfree(notice_msg); notice_msg = NULL;}
    if (err_msg) {pfree(err_msg); err_msg = NULL;}
    if (knapsack_items) {pfree(knapsack_items); knapsack_items = NULL;}

    pgr_SPI_finish();

}



PGDLLEXPORT Datum
_vrp_knapsack(PG_FUNCTION_ARGS) {
    FuncCallContext     *funcctx;
    TupleDesc            tuple_desc;

    Knapsack_rt *result_tuples = 0;
    size_t result_count = 0;

    if (SRF_IS_FIRSTCALL()) {
        MemoryContext   oldcontext;
        funcctx = SRF_FIRSTCALL_INIT();
        oldcontext = MemoryContextSwitchTo(funcctx->multi_call_memory_ctx);

        process(
                text_to_cstring(PG_GETARG_TEXT_P(0)), 
                PG_GETARG_INT32(1),
                &result_tuples,
                &result_count);

        funcctx->max_calls = result_count;
        funcctx->user_fctx = result_tuples;
        if (get_call_result_type(fcinfo, NULL, &tuple_desc)
                != TYPEFUNC_COMPOSITE) {
            ereport(ERROR,
                    (errcode(ERRCODE_FEATURE_NOT_SUPPORTED),
                     errmsg("function returning record called in context "
                         "that cannot accept type record")));
        }

        funcctx->tuple_desc = tuple_desc;
        MemoryContextSwitchTo(oldcontext);
    }

    funcctx = SRF_PERCALL_SETUP();
    tuple_desc = funcctx->tuple_desc;
    result_tuples = (Knapsack_rt*) funcctx->user_fctx;

    if (funcctx->call_cntr <  funcctx->max_calls) {
        HeapTuple   tuple;
        Datum       result;
        Datum       *values;
        bool*       nulls;
        size_t      call_cntr = funcctx->call_cntr;

        size_t numb = 13;
        values = palloc(numb * sizeof(Datum));
        nulls = palloc(numb * sizeof(bool));

        size_t i;
        for (i = 0; i < numb; ++i) {
            nulls[i] = false;
        }

        values[0] = Int32GetDatum(funcctx->call_cntr + 1);
        values[1] = Int32GetDatum(result_tuples[call_cntr].item_weight);
        values[2] = Int64GetDatum(result_tuples[call_cntr].item_cost);

        tuple = heap_form_tuple(tuple_desc, values, nulls);
        result = HeapTupleGetDatum(tuple);
        SRF_RETURN_NEXT(funcctx, result);
    } else {
        SRF_RETURN_DONE(funcctx);
    }
}
