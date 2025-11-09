-- @title strata
-- @author Justin, Justinwhite.work, hmu@justinwhite.work
-- @version 0.1.38
-- @date 2025-8-11
-- @description A really bad implementation of a linear time regex engine inspired by googles RE2
--
-- todo: complete rewrite, improve pattern support, add more tests, improve doccumentation

local strata = {}

-- hash utility
-- @return hash utils
strata.hash = function()
  local hash = {}

  -- random 32 bit integer
  -- @return integer
  hash.rand32 = function()
    return bit32.bor(bit32.lshift(math.random(0, 0xFFFF), 16), math.random(0, 0xFFFF))
  end

  -- combine 32 bit integers
  -- @param a : integer
  -- @param b : integer
  -- @return integer
  hash.mix32 = function(a, b)
    return (bit32.rrotate(bit32.bxor(a, b), (b % 31) + 1) + a + b) % 0xFFFFFFFF
  end

  -- generate a random hash
  -- @param blocks : number of 32 bit blocks to generate (blocks:bits, 1:32, 2:64, 3:96, etc)
  -- @return string : hex string of the generated hash
  hash.gen = function(blocks)
    if not blocks then blocks = 4 end
    assert(blocks >= 1, "[strata]" .. " hash.gen requires atleast 1 block!")

    local gRoot, gBlocks = hash.rand32(), {}
    for i = 1, blocks do
      gBlocks[i] = string.format("%08x", hash.mix32(gRoot, hash.rand32()))
    end

    return table.concat(gBlocks)
  end

  return hash
end

strata.sDFA = function()
  local sDFA = {}

  --
  -- Utilities
  sDFA.utils = {}
  --

  -- Convert a pattern into individual tokens
  -- @param pattern : string
  -- @return table {type, value} : tokens
  sDFA.utils.tokenize = function(pattern)
    local tokens = {}
    for i = 1, #pattern do
      local char = string.sub(pattern, i, i)
      if char:match("[%w]") then
        table.insert(tokens, { type = "literal", value = char })
      elseif char == "*" or char == "+" or char == "?" or char == "|" or char == "(" or char == ")" then
        table.insert(tokens, { type = char })
      else
        error("[strata] ".."Unsupported character: " .. char)
      end
    end
    return tokens
  end

  -- Parse a pattern into an abstract syntax tree (AST)
  -- @param pattern : string
  -- @return table : AST
  sDFA.utils.parse = function(pattern)
    local pos = 1
    local tokens = sDFA.utils.tokenize(pattern)

    local function peek() return tokens[pos] end
    local function nextToken() pos = pos + 1; return tokens[pos-1] end

    -- parse factor: literal, parenthesis, or unary
    local function factor()
      local tok = nextToken()
      if tok.type == "literal" then
        local node = { type="literal", value=tok.value }
        local nextTok = peek()
        if nextTok and (nextTok.type=="*" or nextTok.type=="+" or nextTok.type=="?") then
          node = { type=nextTok.type, sub=node }
          nextToken()
        end
        return node
      elseif tok.type == "(" then
        local node = expr()
        assert(nextToken().type == ")", "Expected closing )")
        local nextTok = peek()
        if nextTok and (nextTok.type=="*" or nextTok.type=="+" or nextTok.type=="?") then
          node = { type=nextTok.type, sub=node }
          nextToken()
        end
        return node
      else
        error("Unexpected token: "..tok.type)
      end
    end

    -- parse concatenation
    local function concat()
      local nodes = { factor() }
      while true do
        local tok = peek()
        if not tok or tok.type == "|" or tok.type == ")" then break end
        table.insert(nodes, factor())
      end
      if #nodes == 1 then return nodes[1] end
      local node = { type="concat", left=nodes[1], right=nodes[2] }
      for i=3,#nodes do
        node = { type="concat", left=node, right=nodes[i] }
      end
      return node
    end

    -- parse alternation
    function expr()
      local node = concat()
      while peek() and peek().type == "|" do
        nextToken()
        node = { type="alt", left=node, right=concat() }
      end
      return node
    end

    return expr()
  end

  -- Compile an AST into an NFA
  -- @param node : table : AST
  -- @param sDFA : table : sDFA instance
  -- @return table : NFA
  sDFA.utils.compile = function(node, sDFA)
    local t = node.type
    if t == "literal" then
      return sDFA.constructs.literal(node.value)
    elseif t == "concat" then
      return sDFA.constructs.concat(sDFA.utils.compile(node.left, sDFA), sDFA.utils.compile(node.right, sDFA))
    elseif t == "alt" then
      return sDFA.constructs.alt(sDFA.utils.compile(node.left, sDFA), sDFA.utils.compile(node.right, sDFA))
    elseif t == "*" then
      return sDFA.constructs.star(sDFA.utils.compile(node.sub, sDFA))
    elseif t == "+" then
      -- a+ = a concat a*
      local subNFA = sDFA.utils.compile(node.sub, sDFA)
      return sDFA.constructs.concat(subNFA, sDFA.constructs.star(subNFA))
    elseif t == "?" then
      -- a? = a | ε
      local subNFA = sDFA.utils.compile(node.sub, sDFA)
      local epsilon = sDFA.constructs.literal("") -- empty match
      return sDFA.constructs.alt(subNFA, epsilon)
    else
      error("Unknown node type: "..t)
    end
  end

  -- Generate a new state ID
  -- @return string : state ID
  sDFA.utils.newStateGen = function()
    local uid = 0
    return function()
      uid = uid + 1
      return "u" .. uid
    end
  end

  -- Create a new state ID
  -- @return string : state ID
  sDFA.utils.newState = sDFA.utils.newStateGen()

  -- Create a new DFA
  -- @param states : table : list of states
  -- @param start : string : start state
  -- @param accept : table : list of accept states
  -- @param transitions : table : transitions
  -- @return table : DFA
  sDFA.utils.newDFA = function(states, start, accept, transitions)
    return {
      states = states,
      start = start,
      accept = accept,
      transitions = transitions
    }
  end

  -- Create a new closure
  -- @param nfa : table : NFA
  -- @param states : table : list of states
  -- @return table : closure
  sDFA.utils.newClosure = function(nfa, states)
    local stack, closure = {}, {}
    for k, v in pairs(states) do
      stack[#stack + 1] = v
      closure[v] = true
    end
    while #stack > 0 do
      local state = table.remove(stack)
      local epsilon = nfa.transitions[state] and nfa.transitions[state]["ε"]
      if epsilon then
        for k, v in pairs(epsilon) do
          if not closure[v] then
            closure[v] = true
            stack[#stack + 1] = v
          end
        end
      end
    end
    local result = {}
    for k, v in pairs(closure) do table.insert(result, k) end
    return result
  end

  --
  -- Constructs
  sDFA.constructs = {}
  --

  -- Create a new literal DFA
  sDFA.constructs.literal = function(char)
    local stateA, stateB = sDFA.utils.newState(), sDFA.utils.newState()
    return sDFA.utils.newDFA(
      { stateA, stateB }, stateA, { [stateB] = true }, { [stateA] = { [char] = { stateB } } }
    )
  end

  -- Concatenate two DFAs
  sDFA.constructs.concat = function(A, B)
    local states = {}
    for k, v in pairs(A.states) do table.insert(states, v) end
    for k, v in pairs(B.states) do table.insert(states, v) end

    local transitions = {}
    for k, v in pairs(A.transitions) do transitions[k] = v end
    for k, v in pairs(B.transitions) do transitions[k] = v end

    for k, v in pairs(A.accept) do
      transitions[k] = transitions[k] or {}
      transitions[k]["ε"] = transitions[k]["ε"] or {}
      table.insert(transitions[k]["ε"], B.start)
    end

    return sDFA.utils.newDFA(states, A.start, B.accept, transitions)
  end

  -- Alternate two DFAs
  sDFA.constructs.alt = function(A, B)
    local state = sDFA.utils.newState()
    local states = { state }
    for k, v in ipairs(A.states) do table.insert(states, v) end
    for k, v in ipairs(B.states) do table.insert(states, v) end

    local transitions = {}
    for k, v in pairs(A.transitions) do transitions[k] = v end
    for k, v in pairs(B.transitions) do transitions[k] = v end
    transitions[state] = { ["ε"] = { A.start, B.start } }

    local accept = {}
    for k, v in pairs(A.accept) do accept[k] = true end
    for k, v in pairs(B.accept) do accept[k] = true end

    return sDFA.utils.newDFA(states, state, accept, transitions)
  end

  -- Kleene star (A*)
  sDFA.constructs.star = function(A)
    local start = sDFA.utils.newState()
    local states = { start }
    for k, v in ipairs(A.states) do table.insert(states, v) end

    local transitions = {}
    for k, v in pairs(A.transitions) do transitions[k] = v end
    transitions[start] = { ["ε"] = { A.start } }
    -- loop back accept states to start
    for k, v in pairs(A.accept) do
      transitions[k] = transitions[k] or {}
      transitions[k]["ε"] = transitions[k]["ε"] or {}
      table.insert(transitions[k]["ε"], A.start)
    end

    local accept = { [start] = true }
    for k, v in pairs(A.accept) do accept[k] = true end

    return sDFA.utils.newDFA(states, start, accept, transitions)
  end

  -- Run the DFA on an input string
  -- @param nfa : table : NFA
  -- @param input : string : input string/pattern
  -- @return boolean : true if the input string is accepted, false otherwise
  sDFA.run = function(nfa, input)
    local current = sDFA.utils.newClosure(nfa, { nfa.start })
    for i = 1, #input do
      local c = input:sub(i, i)
      local nextStates = {}
      for _, state in ipairs(current) do
        local targets = nfa.transitions[state] and nfa.transitions[state][c]
        if targets then
          for _, t in ipairs(targets) do nextStates[t] = true end
        end
      end
      local nextList = {}
      for s, _ in pairs(nextStates) do table.insert(nextList, s) end
      current = sDFA.utils.newClosure(nfa, nextList)
    end
    for _, s in ipairs(current) do
      if nfa.accept[s] then return true end
    end
    return false
  end

  return sDFA
end

return strata
