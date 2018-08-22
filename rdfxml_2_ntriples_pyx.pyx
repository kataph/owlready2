# -*- coding: utf-8 -*-
# Owlready2
# Copyright (C) 2013-2018 Jean-Baptiste LAMY
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

import sys, xml, xml.parsers.expat
from collections import defaultdict

from owlready2.base import OwlReadyOntologyParsingError


def parse_rdfxml(object f, object on_prepare_triple = None, object new_blank = None, object new_literal = None, str default_base = ""):
  cdef object parser = xml.parsers.expat.ParserCreate(None, "")
  try:
    parser.buffer_text          = True
    parser.specified_attributes = True
  except: pass
  
  cdef list stack                    = [["", ""]] # List of [parse type, value] pairs
  cdef dict prefixes                 = {}
  cdef list prefixess                = [prefixes]
  cdef bint tag_is_predicate         = False
  cdef int current_blank             = 0
  cdef int current_fake_blank        = 0
  cdef str current_content           = ""
  cdef dict current_attrs            = None
  cdef int nb_triple                 = 0
  cdef object bns                    = defaultdict(set)
  cdef bint dont_create_unnamed_bn   = False
  cdef dict axiom_annotation_sources = {}
  cdef dict axiom_annotation_props   = {}
  cdef dict axiom_annotation_targets = {}
  cdef object triples_with_unnamed_bn= defaultdict(list)
  
  cdef xml_base, xml_dir
  
  if default_base:
    xml_base = default_base
    if xml_base.endswith("#") or xml_base.endswith("/"): xml_base = xml_base[:-1]
    xml_dir  = xml_base.rsplit("/", 1)[0] + "/"
  else:
    xml_base                 = ""
    xml_dir                  = ""
    
  if not on_prepare_triple:
    def on_prepare_triple(str s, str p, str o):
      nonlocal nb_triple
      nb_triple += 1
      if not s.startswith("_"): s = "<%s>" % s
      if not (o.startswith("_") or o.startswith('"')): o = "<%s>" % o
      print("%s %s %s ." % (s,"<%s>" % p,o))
      
  if not new_blank:
    def new_blank():
      nonlocal current_blank
      current_blank += 1
      return "_:%s" % current_blank
    
  def new_fake_blank():
    nonlocal current_fake_blank
    current_fake_blank += 1
    return "_ %s" % current_fake_blank
  
  cdef object node_2_blanks = defaultdict(new_blank)
  cdef set known_nodes      = set()
  
  if not new_literal:
    def new_literal(str value, dict attrs):
      value = value.replace('"', '\\"').replace("\n", "\\n")
      cdef str lang = attrs.get("http://www.w3.org/XML/1998/namespacelang")
      if lang: return '"%s"@%s' % (value, lang)
      cdef str datatype = attrs.get("http://www.w3.org/1999/02/22-rdf-syntax-ns#datatype")
      if datatype: return '"%s"^^<%s>' % (value, datatype)
      return '"%s"' % (value)
    
  def new_list(list l):
    cdef str bn
    cdef str bn0
    cdef str bn_next
    cdef int i
    
    bn = bn0 = new_blank()
    
    if l:
      for i in range(len(l) - 1):
        on_prepare_triple(bn, "http://www.w3.org/1999/02/22-rdf-syntax-ns#first", l[i])
        bn_next = new_blank()
        on_prepare_triple(bn, "http://www.w3.org/1999/02/22-rdf-syntax-ns#rest", bn_next)
        bn = bn_next
      on_prepare_triple(bn, "http://www.w3.org/1999/02/22-rdf-syntax-ns#first", l[-1])
      on_prepare_triple(bn, "http://www.w3.org/1999/02/22-rdf-syntax-ns#rest", "http://www.w3.org/1999/02/22-rdf-syntax-ns#nil")
      
    else:
      on_prepare_triple(bn, "http://www.w3.org/1999/02/22-rdf-syntax-ns#first", "http://www.w3.org/1999/02/22-rdf-syntax-ns#nil")
      on_prepare_triple(bn, "http://www.w3.org/1999/02/22-rdf-syntax-ns#rest",  "http://www.w3.org/1999/02/22-rdf-syntax-ns#nil")
      
    return bn0
  
  def add_to_bn(str bn, str type, str rel, value):
    nonlocal bns, known_nodes
    if type == "COL":
      value = tuple(frozenset(bns[v])
                    if v.startswith("_") and (not v in known_nodes)
                    else v
                    for v in value)
      bns[bn].add((type, rel) + value)
    else:
      if value.startswith("_") and (not value in known_nodes): value = frozenset(bns[value])
      bns[bn].add((type, rel, value))
      
  def startNamespace(str prefix, str uri):
    nonlocal prefixess, prefixes
    prefixes = prefixes.copy()
    prefixess.append(prefixes)
    
    if prefix: prefixes[prefix  ] = uri
    else:      prefixes[""      ] = uri
      
  def endNamespace(str prefix):
    nonlocal prefixess, prefixes
    prefixess.pop()
    prefixes = prefixess[-1]
    
  def startElement(str tag, dict attrs):
    nonlocal tag_is_predicate, stack, current_content, current_attrs, dont_create_unnamed_bn, xml_base, xml_dir, known_nodes, node_2_blanks
    cdef str iri
    cdef str namespace_base
    
    tag_is_predicate = not tag_is_predicate
    if tag_is_predicate:
      
      if   attrs.get("http://www.w3.org/1999/02/22-rdf-syntax-ns#parseType") == "Collection":
        stack.append(["Collection", []])
        
      elif tag == "http://www.w3.org/1999/02/22-rdf-syntax-ns#RDF":
        stack.append(["RDF", ""])
        
        namespace_base = attrs.get("http://www.w3.org/XML/1998/namespacebase")
        if namespace_base:
          xml_base = namespace_base
          xml_dir  = namespace_base.rsplit("/", 1)[0] + "/"
          
      else:
        iri = attrs.get("http://www.w3.org/1999/02/22-rdf-syntax-ns#resource")
        if iri:
          if not ":" in iri:
            if not iri:                 iri = xml_base
            elif   iri.startswith("#"): iri = xml_base + iri
            elif   iri.startswith("/"): iri = xml_dir  + iri[1:]
            else:                       iri = xml_dir  + iri
          stack.append(["Resource", iri])
          
        else:
          iri = attrs.get("http://www.w3.org/1999/02/22-rdf-syntax-ns#nodeID")
          
          if iri:
            iri = node_2_blanks[iri]
            known_nodes.add(iri)
            stack.append(["Resource", iri])
          else:
            stack.append(["Literal", ""])
            current_content = ""
            current_attrs   = attrs
            
          if (tag == "http://www.w3.org/2002/07/owl#annotatedSource") or (tag == "http://www.w3.org/2002/07/owl#annotatedTarget"):
            dont_create_unnamed_bn = True
            
    else:
      iri = attrs.get("http://www.w3.org/1999/02/22-rdf-syntax-ns#about", None)
      if iri is None:
        iri = attrs.get("http://www.w3.org/1999/02/22-rdf-syntax-ns#ID", None)
        if iri: iri = "#%s" % iri
      if iri is None:
        iri = attrs.get("http://www.w3.org/1999/02/22-rdf-syntax-ns#nodeID")
        if iri:
          iri = node_2_blanks[iri]
          known_nodes.add(iri)
        else:
          if dont_create_unnamed_bn: iri = new_fake_blank()
          else:                      iri = new_blank()
      else:
        if not ":" in iri:
          if not iri:                 iri = xml_base
          elif   iri.startswith("#"): iri = xml_base + iri
          elif   iri.startswith("/"): iri = xml_dir  + iri[1:]
          else:                       iri = xml_dir  + iri
          
      if tag != "http://www.w3.org/1999/02/22-rdf-syntax-ns#Description":
        if not iri.startswith("_ "):
          on_prepare_triple(iri, "http://www.w3.org/1999/02/22-rdf-syntax-ns#type", tag)
        if iri.startswith("_"):
          add_to_bn(iri, "REL", "http://www.w3.org/1999/02/22-rdf-syntax-ns#type", tag)
          
      if stack[-1][0] == "Collection":
        stack[-1][1].append(iri)
        
      else:
        if stack[-1][0] == "Literal": stack[-1][0] = "Resource"
        stack[-1][1] = iri
        
        
  def endElement(str tag):
    nonlocal tag_is_predicate, dont_create_unnamed_bn,  stack, axiom_annotation_sources, axiom_annotation_props, axiom_annotation_targets, triples_with_unnamed_bn
    cdef str iri
    cdef str parse_type
    cdef object value
    cdef list triples
    
    if tag_is_predicate:
      parse_type, value = stack.pop()
      
      if stack[-1][0] == "Collection": iri = stack[-1][1][-1]
      else:                            iri = stack[-1][1]
      
      if   tag == "http://www.w3.org/2002/07/owl#annotatedSource":
        dont_create_unnamed_bn = False
        axiom_annotation_sources[iri] = value
        if isinstance(value, str) and value.startswith("_ "):
          triples_with_unnamed_bn[iri].insert(0, (tag, value, parser.CurrentLineNumber, parser.CurrentColumnNumber))
          
          tag_is_predicate = not tag_is_predicate
          return
        
      elif tag == "http://www.w3.org/2002/07/owl#annotatedProperty":
        axiom_annotation_props  [iri] = value
      
      elif tag == "http://www.w3.org/2002/07/owl#annotatedTarget":
        dont_create_unnamed_bn = False
        axiom_annotation_targets[iri] = value
        if isinstance(value, str) and value.startswith("_ "):
          triples_with_unnamed_bn[iri].append((tag, value, parser.CurrentLineNumber, parser.CurrentColumnNumber))
          
          tag_is_predicate = not tag_is_predicate
          return
        
      
      if   parse_type == "Resource":
        if not iri.startswith("_ "):
          on_prepare_triple(iri, tag, value)
          
        if iri.startswith("_"):
          add_to_bn(iri, "REL", tag, value)
            
        if value.startswith("_"):
          add_to_bn(value, "INV", tag, iri)
          
          
      elif parse_type == "Literal":
        value = new_literal(current_content, current_attrs)
        if not iri.startswith("_ "):
          on_prepare_triple(iri, tag, value)
        if iri.startswith("_"):
          add_to_bn(iri, "REL", tag, value)
          
      elif parse_type == "Collection":
        if not iri.startswith("_ "):
          on_prepare_triple(iri, tag, new_list(value))
        if iri.startswith("_"):
          add_to_bn(iri, "COL", tag, value)
          
          
    tag_is_predicate = not tag_is_predicate
    
    
  def characters(str content):
    nonlocal current_content,  stack
    if stack[-1][0] == "Literal": current_content += content
    
    
  parser.StartNamespaceDeclHandler = startNamespace
  parser.EndNamespaceDeclHandler   = endNamespace
  parser.StartElementHandler       = startElement
  parser.EndElementHandler         = endElement
  parser.CharacterDataHandler      = characters
  
  try:
    if isinstance(f, str):
      f = open(f, "rb")
      parser.ParseFile(f)
      f.close()
    else:
      parser.ParseFile(f)
  except Exception as e:
    raise OwlReadyOntologyParsingError("RDF/XML parsing error in file %s, line %s, column %s." % (getattr(f, "name", "???"), parser.CurrentLineNumber, parser.CurrentColumnNumber)) from e
  
  cdef object content_2_bns
  cdef str bn
  cdef set content
  if triples_with_unnamed_bn:
    content_2_bns = defaultdict(list)
    for bn, content in bns.items():
      if not bn.startswith("_ "):
        content_2_bns[frozenset(content)].append(bn)
        
    def rebuild_bn(object content):
      nonlocal content_2_bns
      cdef str bn = new_blank()
      content_2_bns[frozenset(content)].append(bn)
      cdef tuple i
      cdef object drop
      cdef str p
      cdef object o
      cdef list l
      for i in content:
        if   i[0] == "REL":
          drop, p, o = i
          if not isinstance(o, str): o = rebuild_bn(o)
          on_prepare_triple(bn, p, o)
        elif i[0] == "INV":
          drop, p, o = i
          if not isinstance(o, str): o = rebuild_bn(o)
          on_prepare_triple(o, p, bn)
        elif i[0] == "COL":
          drop, p, *l = i
          l = [(isinstance(x, str) and x) or rebuild_bn(x) for x in l]
          o = new_list(l)
          on_prepare_triple(bn, p, o)
        else:
          print(i)
          raise ValueError
      return bn
    
    for axiom_iri, triples in triples_with_unnamed_bn.items():
      for p, o, line, column in triples:
        try:
          content = bns[o]
          if p == "http://www.w3.org/2002/07/owl#annotatedSource":
            target = axiom_annotation_targets[axiom_iri]
            if target.startswith("_"): target = frozenset(bns[target])
            candidates_bn = content_2_bns[frozenset(content | { ("REL", axiom_annotation_props[axiom_iri], target) })]
            
          else:
            source = axiom_annotation_sources[axiom_iri]
            if source.startswith("_"):
              source = frozenset(bns[source] | { ("REL", axiom_annotation_props[axiom_iri], target) })
            candidates_bn = (content_2_bns[frozenset(content | { ("INV", axiom_annotation_props[axiom_iri], source) })] or
                             content_2_bns[frozenset(content)])
            
          if candidates_bn: o = candidates_bn[-1]
          else:
            o = rebuild_bn(content)
          on_prepare_triple(axiom_iri,p,o)
        except Exception as e:
          raise OwlReadyOntologyParsingError("RDF/XML parsing error in file %s, line %s, column %s." % (getattr(f, "name", "???"), line, column)) from e
        
    
  return nb_triple


def _create_triplelite_func(object abbreviate, list values, str datatype_attr):
  def on_prepare_triple(str s, str p, str o):
    nonlocal values
    
    if not s.startswith("_"): s = abbreviate(s)
    p = abbreviate(p)
    if not (o.startswith("_") or o.startswith('"')): o = abbreviate(o)
    
    values.append((s,p,o))
    
  def new_literal(str value, dict attrs):
    nonlocal datatype_attr
    cdef str lang = attrs.get("http://www.w3.org/XML/1998/namespacelang")
    if lang: return '"%s"@%s' % (value, lang)
    cdef str datatype = attrs.get(datatype_attr)
    if datatype: return '"%s"%s' % (value, abbreviate(datatype))
    return '"%s"' % (value)
  
  return on_prepare_triple, new_literal
