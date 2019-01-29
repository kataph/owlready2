# -*- coding: utf-8 -*-
# Owlready2
# Copyright (C) 2017-2018 Jean-Baptiste LAMY
# LIMICS (Laboratoire d'informatique médicale et d'ingénierie des connaissances en santé), UMR_S 1142
# University Paris 13, Sorbonne paris-Cité, Bobigny, France

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Lesser General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Lesser General Public License for more details.

# You should have received a copy of the GNU Lesser General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

import rdflib, rdflib.store
from rdflib import URIRef, BNode, Literal

from owlready2.base import from_literal

class TripleLiteRDFlibStore(rdflib.store.Store):
  context_aware = True
  
  def __init__(self, world):
    self.world      = world
    self.triplelite = world.graph
    super().__init__()
    
    self.main_graph            = TripleLiteRDFlibGraph(store = self)
    self.main_graph.onto       = None
    self.main_graph.triplelite = self.triplelite
    
    self.context_graphs = {}
    for onto, triplelite in self.triplelite.onto_2_subgraph.items():
      graph            = TripleLiteRDFlibGraph(store = self, identifier = URIRef(onto.base_iri))
      graph.onto       = onto
      graph.triplelite = triplelite
      self.context_graphs[onto] = graph
      
  def _2_python(self, x):
    if   isinstance(x, rdflib.term.URIRef ): return self.world[str(x)]
    elif isinstance(x, rdflib.term.BNode  ): return str(x)
    elif isinstance(x, rdflib.term.Literal): return x.toPython()
    
  def _rdflib_2_owlready(self, spo):
    s,p,o = spo
    if   isinstance(s, rdflib.term.URIRef ): s = self.triplelite._abbreviate(str(s))
    elif isinstance(s, rdflib.term.BNode  ): s = str(s)
    if   isinstance(p, rdflib.term.URIRef ): p = self.triplelite._abbreviate(str(p))
    if   isinstance(o, rdflib.term.URIRef ): o = self.triplelite._abbreviate(str(o)); d = None
    elif isinstance(o, rdflib.term.BNode  ): o = str(o); d = None
    elif isinstance(o, rdflib.term.Literal):
      if o.language is None:
        if o.datatype:
          d = self.triplelite._abbreviate(str(o.datatype))
          if   isinstance(o.value, bool):         o = str(o)
          elif isinstance(o.value, (int, float)): o = o.value
          else:                                   o = str(o)
        else:
          d = ""
          o = str(o)
      else:
        d = "@%s" % o.language
        o = str(o)
    else:
      d = None
    return s,p,o,d
  
  def _owlready_2_rdflib(self, s,p,o,d = None):
    if   s < 0: s = BNode(s)
    else:                   s = URIRef(self.triplelite._unabbreviate(s))
    p = URIRef(self.triplelite._unabbreviate(p))
    if d is None:
      if o < 0: o = BNode(o)
      else:                 o = URIRef(self.triplelite._unabbreviate(o))
    else:
      if   isinstance(d, str) and d.startswith("@"): o = Literal(o, lang = d[1:])
      elif (d == "") or (d == 0):                    o = Literal(o)
      else:                                          o = Literal(o, datatype = URIRef(self.triplelite._unabbreviate(d)))
    return s,p,o
  
  def add(self, xxx_todo_changeme, context, quoted = False):
    s,p,o,d = self._rdflib_2_owlready(xxx_todo_changeme)

    if d is None:
      context.triplelite._add_obj_triple_raw_spo(s,p,o)
    else:
      context.triplelite._add_data_triple_raw_spodd(s,p,o,d)
    #super().add(xxx_todo_changeme, context, quoted)
    
  def remove(self, xxx_todo_changeme, context = None):
    s,p,o,d = self._rdflib_2_owlready(xxx_todo_changeme)
    if d is None:
      context.triplelite._del_obj_triple_raw_spo(s,p,o)
    else:
      context.triplelite._del_data_triple_raw_spodd(s,p,o,d)
    #super().remove(xxx_todo_changeme, context, quoted)
    
  def triples(self, triple_pattern, context = None):
    rs,rp,ro,rd = self._rdflib_2_owlready(triple_pattern)
    
    if   rd is None:
      for s,p,o,d in context.triplelite._get_triples_spod_spod(rs,rp,ro, None):
        yield self._owlready_2_rdflib(s,p,o,d), context
    elif rd is None:
      for s,p,o in context.triplelite._get_obj_triples_spo_spo(rs,rp,ro):
        yield self._owlready_2_rdflib(s,p,o,None), context
    else:
      for s,p,o,d in context.triplelite._get_data_triples_spod_spod(rs,rp,ro, None):
        yield self._owlready_2_rdflib(s,p,o,d), context
        
  def __len__(self, context = None):
    return len(context.triplelite)
  
  def contexts(self, triple = None):
    if triple is None:
      return self.context_graphs.values()
    else:
      triple = self._rdflib_2_owlready(triple)
      for graph in self.context_graphs.values():
        if graph.triplelite.has_triple(*triple): yield graph


class TripleLiteRDFlibGraph(rdflib.Graph):
  def query_owlready(self, query, *args, **kargs):
    r = self.query(query, *args, **kargs)
    for line in r:
      line2 = [self._rdflib_2_owlready(i) for i in line]
      yield line2
      
  def _rdflib_2_owlready(self, o):
    if   isinstance(o, rdflib.term.URIRef ): o = self.store.world[str(o)]
    elif isinstance(o, rdflib.term.BNode  ): o = (self.store.onto or self.store.world)._parse_bnode(o)
    elif isinstance(o, rdflib.term.Literal):
      if o.language is None:
        if o.datatype:
          d = self.triplelite._abbreviate(str(o.datatype))
          o = o.value
        else:
          d = ""
          o = str(o)
      else:
        d = "@%s" % o.language
        o = str(o)
      o = from_literal(o, d)
    return o
