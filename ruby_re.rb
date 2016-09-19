require 'set'

class NFAStateFactory
  class << self
    def create_new(start:)
      @label_counter ||= 0
      state = NFAState.new(@label_counter, start: start)
      @label_counter += 1
      state
    end
  end
end

class NFAState
  attr_accessor :start, :goal
  attr_reader :label

  def initialize(label, start: false)
    @label = label
    @start = start
    @goal  = false
  end

  def ==(other)
    @label == other.label
  end

  def inspect
    "<State:#{@label}#{if @start then ' start' end}#{if @goal then ' goal' end}>"
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

  def goal_state
    @states.find { |state| state.goal }
  end

  def start_state
    @states.find { |state| state.start }
  end
end

class NFACreator
  attr_reader :states, :edges  #  Only for debug

  def initialize(re_str)
    start_state = NFAStateFactory.create_new(start: true)
    @states = [start_state]
    @edges  = []
    @re_str = re_str
    @tokens = StringIO.new(@re_str)
  end

  def add_normal(token)
    from = @states.last
    to = NFAStateFactory.create_new(start: false)
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

  def add_vertical_var(token)
    left_start  = @states.find { |state| state.start }
    left_start.start = false
    left_goal   = @states.last

    right_nfa    = NFACreator.new(@tokens.gets).create
    right_start  = right_nfa.start_state
    right_start.start = false
    right_goal   = right_nfa.goal_state
    right_goal.goal = false

    new_start = NFAStateFactory.create_new(start: true)
    @edges.push(NFAEdge.new(new_start, left_start,  MetaToken::Epsilon))
    @edges.push(NFAEdge.new(new_start, right_start, MetaToken::Epsilon))

    new_goal = NFAStateFactory.create_new(start: false)
    @edges.push(NFAEdge.new(left_goal,  new_goal, MetaToken::Epsilon))
    @edges.push(NFAEdge.new(right_goal, new_goal, MetaToken::Epsilon))

    @states += right_nfa.states
    @states.push(new_start)
    @states.push(new_goal)

    @edges += right_nfa.edges
  end

  def create
    while token = @tokens.getc
      case token
      when '|'
        add_vertical_var(token)
      when '*'
        add_star(token)
      else
        add_normal(token)
      end
    end
    @states.last.goal = true
    NFA.new(@states, @edges)
  end
end

class DFAState
  attr_reader :nfa_states, :start, :goal

  def initialize(nfa_states, nfa)
    @nfa_states = Set.new(nfa_states)
    @nfa        = nfa
    @start      = false
    @goal       = false
    expand_states
    set_flags
  end

  def nfa_edges
    @nfa_edges ||= nfa_states.to_a.map { |nfa_state|
      @nfa.edges_from(nfa_state)
    }.flatten.select { |edge| edge.token != MetaToken::Epsilon }
  end

  def ==(other)
    @nfa_states == other.nfa_states
  end

  def inspect
    "<State:{#{nfa_states.map(&:label).join(', ')}}#{if @start then ' start' end}#{if @goal then ' goal' end}>"
  end

  def to_s
    inspect
  end

  private
  def expand_states
    changed = true
    while changed
      changed = false
      @nfa_states.to_a.each do |nfa_state|
        @nfa.epsilon_edges_from(nfa_state).each do |edge|
          if !@nfa_states.include?(edge.to)
            @nfa_states.add(edge.to)
            changed = true
          end
        end
      end
    end
  end

  def set_flags
    @nfa_states.each do |nfa_state|
      @start = true if nfa_state.start
      @goal  = true if nfa_state.goal
    end
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
  attr_writer :current_state

  def initialize(states, edges)
    @states        = states
    @edges         = edges
    @current_state = start_states.first
  end

  def goal?
    @current_state.goal
  end

  def refresh
    @current_state = start_states.first
  end

  def start_states
    states.select { |state| state.start }
  end

  def translate_by(token)
    next_state = @edges.find { |edge| edge.from == @current_state && edge.token == token }&.to
    if next_state
      @current_state = next_state
      true
    else
      false
    end
  end
end

class DFAConverter
  def initialize(nfa)
    @nfa          = nfa
    start_state = DFAState.new([@nfa.start_state], @nfa)
    @states       = [start_state]
    @edges        = []
    @search_queue = [start_state]
  end

  def convert
    while @search_queue.length > 0
      add_state
    end
    DFA.new(@states, @edges)
  end

  private
  def add_state
    from = @search_queue.shift
    from.nfa_edges.group_by { |edge| edge.token }.map do |token, edges|
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
end

class ReEngine
  attr_reader :nfa, :dfa

  def initialize(re_str)
    @nfa = NFACreator.new(re_str).create
    @dfa = DFAConverter.new(nfa).convert
  end

  def match(str)
    result = _match(str)
    @dfa.refresh
    result
  end

  private
  def _match(str)
    @dfa.start_states.each do |start_state|
      @dfa.current_state = start_state
      tokenize(str).each do |token|
        return false if !@dfa.translate_by(token)
      end
      return true if @dfa.goal?
    end
    false
  end

  def tokenize(str)
    StringIO.new(str).each_char
  end
end

re = ReEngine.new('b*a*bcd*')
p re.nfa.states
p re.nfa.edges
p re.dfa.states
p re.dfa.edges
p re.match('ab')
p re.match('acdd')
p re.match('abcdd')
re2 = ReEngine.new('abc|de')
p re2.nfa.states
p re2.nfa.edges
p re2.dfa.states
p re2.dfa.edges
p re2.match('ab')
p re2.match('abc')
p re2.match('d')
p re2.match('de')
# >> [<State:0 start>, <State:1>, <State:2>, <State:3>, <State:4>, <State:5 goal>]
# >> [<Edge:b <State:0 start>-<State:1>>, <Edge:Epsilon <State:1>-<State:0 start>>, <Edge:Epsilon <State:0 start>-<State:1>>, <Edge:a <State:1>-<State:2>>, <Edge:Epsilon <State:2>-<State:1>>, <Edge:Epsilon <State:1>-<State:2>>, <Edge:b <State:2>-<State:3>>, <Edge:c <State:3>-<State:4>>, <Edge:d <State:4>-<State:5 goal>>, <Edge:Epsilon <State:5 goal>-<State:4>>, <Edge:Epsilon <State:4>-<State:5 goal>>]
# >> [<State:{0, 1, 2} start>, <State:{1, 3, 0, 2} start>, <State:{4, 5} goal>]
# >> [<Edge:b <State:{0, 1, 2} start>-<State:{1, 3, 0, 2} start>>, <Edge:a <State:{0, 1, 2} start>-<State:{0, 1, 2} start>>, <Edge:a <State:{1, 3, 0, 2} start>-<State:{0, 1, 2} start>>, <Edge:c <State:{1, 3, 0, 2} start>-<State:{4, 5} goal>>, <Edge:b <State:{1, 3, 0, 2} start>-<State:{1, 3, 0, 2} start>>, <Edge:d <State:{4, 5} goal>-<State:{4, 5} goal>>]
# >> false
# >> false
# >> true
# >> [<State:6>, <State:7>, <State:8>, <State:9>, <State:10>, <State:11>, <State:12>, <State:13 start>, <State:14 goal>]
# >> [<Edge:a <State:6>-<State:7>>, <Edge:b <State:7>-<State:8>>, <Edge:c <State:8>-<State:9>>, <Edge:Epsilon <State:13 start>-<State:6>>, <Edge:Epsilon <State:13 start>-<State:10>>, <Edge:Epsilon <State:9>-<State:14 goal>>, <Edge:Epsilon <State:12>-<State:14 goal>>, <Edge:d <State:10>-<State:11>>, <Edge:e <State:11>-<State:12>>]
# >> [<State:{13, 6, 10} start>, <State:{7}>, <State:{11}>, <State:{8}>, <State:{12, 14} goal>, <State:{9, 14} goal>]
# >> [<Edge:a <State:{13, 6, 10} start>-<State:{7}>>, <Edge:d <State:{13, 6, 10} start>-<State:{11}>>, <Edge:b <State:{7}>-<State:{8}>>, <Edge:e <State:{11}>-<State:{12, 14} goal>>, <Edge:c <State:{8}>-<State:{9, 14} goal>>]
# >> false
# >> true
# >> false
# >> true
