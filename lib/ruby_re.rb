require 'set'

class NFAState
  attr_reader :label

  def initialize(label)
    @label = label
  end

  def ==(other)
    @label == other.label
  end

  def inspect
    "<State:#{@label}>"
  end

  def to_s
    inspect
  end
end

class NFAEdge
  attr_reader :from, :to, :token

  def initialize(from, to, token)
    @from  = from
    @to    = to
    @token = token
  end

  def inspect
    "<Edge:#{@token} #{@from}-#{@to}>"
  end

  def to_s
    inspect
  end
end

module MetaToken
  Epsilon = :Epsilon
end

class ParseError < StandardError; end

class NFA
  attr_reader :states, :edges

  def initialize(states, edges)
    @states = states
    @edges  = edges
  end

  def edges_from(from)
    @edges.select { |edge| edge.from == from }
  end

  def epsilon_edges_from(from)
    edges_from(from).select { |edge| edge.token == MetaToken::Epsilon }
  end

  def first_state
    @states.first
  end
end

class NFACreator
  attr_reader :states, :edges  #  Only for debug

  def initialize(re_str)
    first_state = NFAState.new(0)
    @states = [first_state]
    @edges  = []
    @re_str = re_str
  end

  def add_normal(token)
    from = @states.last
    to = NFAState.new(@states.length)
    @states.push(to)
    @edges.push(NFAEdge.new(from, to, token))
  end

  def add_star(token)
    if @states.length < 2
      raise ParseError.new("SyntaxError: target of repeat operator is not specified: /#{@re_str}/")
    end
    pre_last = @states[-2]
    last     = @states.last
    @edges.push(NFAEdge.new(last, pre_last, MetaToken::Epsilon))
    @edges.push(NFAEdge.new(pre_last, last, MetaToken::Epsilon))
  end

  # TODO(south37) Accept `|`
  def create
    tokens.each do |token|
      case token
      when '*'
        add_star(token)
      else
        add_normal(token)
      end
    end
    NFA.new(@states, @edges)
  end

  def tokens
    StringIO.new(@re_str).each_char
  end
end

class DFAState
  attr_reader :nfa_states

  def initialize(nfa_states, nfa)
    @nfa_states = Set.new(nfa_states)
    @nfa        = nfa
    add_by_epsilon
  end

  def add_by_epsilon
    @nfa_states.to_a.each do |nfa_state|
      @nfa.epsilon_edges_from(nfa_state).each do |edge|
        @nfa_states.add(edge.to)
      end
    end
  end

  def ==(other)
    @nfa_states == other.nfa_states
  end

  def inspect
    "<State:{#{nfa_states.map(&:label).join(', ')}}>"
  end

  def to_s
    inspect
  end
end

class DFAEdge
  attr_reader :from, :to, :token

  def initialize(from, to, token)
    @from  = from
    @to    = to
    @token = token
  end

  def ==(other)
    @from == other.from && @to == other.to && @token == other.token
  end

  def inspect
    "<Edge:#{@token} #{@from}-#{@to}>"
  end

  def to_s
    inspect
  end
end

class DFA
  attr_reader :states, :edges

  def initialize(states, edges)
    @states = states
    @edges  = edges
  end
end

class DFAConverter
  def initialize(nfa)
    @nfa          = nfa
    first_state = DFAState.new([@nfa.first_state], @nfa)
    @states       = [first_state]
    @edges        = []
    @search_queue = [first_state]
  end

  def add_state
    from = @search_queue.shift
    nfa_edges = from.nfa_states.to_a.map { |nfa_state| @nfa.edges_from(nfa_state) }.flatten
    nfa_edges.group_by { |edge| edge.token }.select { |token, edges| token != MetaToken::Epsilon }.each do |token, edges|
      to = DFAState.new(edges.map(&:to), @nfa)
      if !@states.include?(to)
        @states.push(to)
        @search_queue.push(to)
      else
        to = @states.select { |state| state == to }.first
      end
      edge = DFAEdge.new(from, to, token)
      @edges.push(edge) unless @edges.include?(edge)
    end
  end

  def convert
    while @search_queue.length > 0
      add_state
    end
    DFA.new(@states, @edges)
  end
end

nfa_creator = NFACreator.new('a*bcd*')
nfa = nfa_creator.create
p nfa.states
p nfa.edges

dfa_converter = DFAConverter.new(nfa)
dfa = dfa_converter.convert
p dfa.states
p dfa.edges
# >> [<State:0>, <State:1>, <State:2>, <State:3>, <State:4>]
# >> [<Edge:a <State:0>-<State:1>>, <Edge:Epsilon <State:1>-<State:0>>, <Edge:Epsilon <State:0>-<State:1>>, <Edge:b <State:1>-<State:2>>, <Edge:c <State:2>-<State:3>>, <Edge:d <State:3>-<State:4>>, <Edge:Epsilon <State:4>-<State:3>>, <Edge:Epsilon <State:3>-<State:4>>]
# >> [<State:{0, 1}>, <State:{2}>, <State:{3, 4}>]
# >> [<Edge:a <State:{0, 1}>-<State:{0, 1}>>, <Edge:b <State:{0, 1}>-<State:{2}>>, <Edge:c <State:{2}>-<State:{3, 4}>>, <Edge:d <State:{3, 4}>-<State:{3, 4}>>]
