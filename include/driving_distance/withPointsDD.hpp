/*PGR-GNU*****************************************************************
File: withPointsDD.hpp

Generated with Template by:
Copyright (c) 2023 pgRouting developers
Mail: project at pgrouting.org

Function's developer:
Copyright (c) 2023 Yige Huang
Mail: square1ge at gmail.com
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
#ifndef INCLUDE_DRIVING_DISTANCE_WITHPOINTSDD_HPP_
#define INCLUDE_DRIVING_DISTANCE_WITHPOINTSDD_HPP_
#pragma once

#include <deque>
#include <set>
#include <vector>
#include <utility>

#include <visitors/dfs_visitor_with_root.hpp>
#include <visitors/edges_order_dfs_visitor.hpp>
#include <boost/graph/filtered_graph.hpp>

#include"c_types/mst_rt.h"


namespace pgrouting {
namespace functions {

template <class G>
class ShortestPath_tree{
     typedef typename G::V V;
     typedef typename G::E E;
     typedef typename G::B_G B_G;


 public:
     std::deque<MST_rt> generate(
             G &graph,
             std::deque<Path> paths,
             std::vector<int64_t> start_vids);


 private:
     /* Functions */
     void clear() {
         m_roots.clear();
     }

     template <typename T>
     std::deque<MST_rt> get_results(
             T order,
             int64_t p_root,
             const G &graph);

     std::deque<MST_rt> dfs_order(const G &graph);

     void get_edges_from_paths(
             const G& graph,
             const std::deque<Path> paths);


 private:
     /* Member */
     std::vector<int64_t> m_roots;

     struct InSpanning {
         std::set<E> edges;
         bool operator()(E e) const { return edges.count(e); }
         void clear() { edges.clear(); }
     } m_spanning_tree;
};


template <class G>
template <typename T>
std::deque<MST_rt>
ShortestPath_tree<G>::get_results(// TODO: can be simplified
        T order,
        int64_t p_root,
        const G &graph) {
    std::deque<MST_rt> results;

    std::vector<double> agg_cost(graph.num_vertices(), 0);
    std::vector<int64_t> depth(graph.num_vertices(), 0);
    int64_t root(p_root);

    for (const auto edge : order) {
        auto u = graph.source(edge);
        auto v = graph.target(edge);
        if (depth[u] == 0 && depth[v] != 0) {
            std::swap(u, v);
        }

        if (depth[u] == 0 && depth[v] == 0) {
            if (!p_root && graph[u].id > graph[v].id) std::swap(u, v);

            root = p_root? p_root: graph[u].id;
            depth[u] = -1;
            results.push_back({
                root,
                    0,
                    graph[u].id,
                    -1,
                    0.0,
                    0.0 });
        }

        agg_cost[v] = agg_cost[u] + graph[edge].cost;
        depth[v] = depth[u] == -1? 1 : depth[u] + 1;

        results.push_back({
            root,
                0,
                graph[v].id,
                graph[edge].id,
                graph[edge].cost,
                agg_cost[v]
        });
    }
    return results;
}

template <class G>
std::deque<MST_rt>
ShortestPath_tree<G>::dfs_order(const G &graph) {
        boost::filtered_graph<B_G, InSpanning, boost::keep_all>
            mstGraph(graph.graph, m_spanning_tree, {});

        std::deque<MST_rt> results;
        for (const auto root : m_roots) {
            std::vector<E> visited_order;

            using dfs_visitor = visitors::Dfs_visitor_with_root<V, E>;
            if (graph.has_vertex(root)) {
                /* abort in case of an interruption occurs (e.g. the query is being cancelled) */
                CHECK_FOR_INTERRUPTS();
                try {
                    boost::depth_first_search(
                            mstGraph,
                            visitor(dfs_visitor(graph.get_V(root), visited_order))
                            .root_vertex(graph.get_V(root)));
                } catch(found_goals &) {
                    {}
                } catch (boost::exception const& ex) {
                    (void)ex;
                    throw;
                } catch (std::exception &e) {
                    (void)e;
                    throw;
                } catch (...) {
                    throw;
                }
                auto result = get_results(visited_order, root, graph);
                results.insert(results.end(), result.begin(), result.end());
            } else {
                results.push_back({root, 0, root, -1, 0.0, 0.0});
            }
        }
        return results;
    }


template <class G>
void
ShortestPath_tree<G>::get_edges_from_paths(
         const G& graph,
         const std::deque<Path> paths){

    // TODO:
    // Extract the corresponding edges from paths and store them in m_spanning_tree
}

template <class G>
std::deque<MST_rt>
ShortestPath_tree<G>::generate(
        G &graph,
        std::deque<Path> paths,
        std::vector<int64_t> start_vids) {

    clear();
    this->m_roots = start_vids;
    get_edges_from_paths(graph, paths);

    return this->dfs_order(graph);
}


}  // namespace functions
}  // namespace pgrouting

#endif // INCLUDE_DRIVING_DISTANCE_WITHPOINTSDD_HPP_