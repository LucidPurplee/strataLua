local strata = require 'strata.strata'
local hash = strata.hash()
local sDFA = strata.sDFA()

local tests = {
  ["ab*"] = {
    ["a"] = true,
    ["ab"] = true,
    ["abbb"] = true,
    ["abx"] = false,
    ["xab"] = false,
    ["b"] = false,
    [""] = false,
  },
  ["a(b|c)d*"] = {
    ["ad"] = true,
    ["abd"] = true,
    ["acd"] = true,
    ["abcd"] = false,
    ["a"] = true,
    ["abdddd"] = true,
    ["acdcd"] = false,
  },
  ["a+b?"] = {
    ["a"] = true,
    ["aa"] = true,
    ["ab"] = true,
    ["aab"] = true,
    ["b"] = false,
    [""] = false,
    ["aaaaaa"] = true,
    ["aaaab"] = true,
  },
  ["(ab|cd)*"] = {
    [""] = true,
    ["ab"] = true,
    ["cd"] = true,
    ["abcd"] = true,
    ["ababcdcd"] = true,
    ["ac"] = false,
    ["ababx"] = false,
  },
  ["a?b+c"] = {
    ["bc"] = true,
    ["abc"] = true,
    ["bbbc"] = true,
    ["ac"] = false,
    ["c"] = false,
    ["abbc"] = true,
  },
  ["(a|b|c)+"] = {
    ["a"] = true,
    ["b"] = true,
    ["c"] = true,
    ["abc"] = true,
    ["aaa"] = true,
    [""] = false,
    ["ccccbbbbaaa"] = true,
    ["d"] = false,
  },
  -- TODO : unsupported character error
  --[[["x(y|z)*w"] = {
    ["xw"] = true,
    ["xyw"] = true,
    ["xzw"] = true,
    ["xyzxw"] = true,
    ["x"] = false,
    ["w"] = false,
    ["xyzyzyw"] = true,
  },]]
  ["^a$"] = {
    ["a"] = true,
    ["aa"] = false,
    [""] = false,
    ["ba"] = false,
  },
  ["^abc$"] = {
    ["abc"] = true,
    ["ab"] = false,
    ["abcd"] = false,
    [""] = false,
  },
  ["a.*b"] = {
    ["ab"] = true,
    ["axb"] = true,
    ["axxxb"] = true,
    ["a"] = false,
    ["b"] = false,
    ["ba"] = false,
    ["abb"] = true,
  },
  ["(ab)+c"] = {
    ["abc"] = true,
    ["ababc"] = true,
    ["c"] = false,
    ["ab"] = false,
    ["abababababc"] = true,
  },
  ["[abc]+"] = {
    ["a"] = true,
    ["b"] = true,
    ["c"] = true,
    ["abc"] = true,
    ["cab"] = true,
    ["d"] = false,
    [""] = false,
  },
  ["[a-z]*"] = {
    ["abc"] = true,
    ["xyz"] = true,
    ["ABC"] = false,
    [""] = true,
    ["a1b2c3"] = false,
  },
  ["[0-9]+"] = {
    ["123"] = true,
    ["0"] = true,
    [""] = false,
    ["abc"] = false,
    ["12a3"] = false,
  },
  ["(foo|bar)?baz"] = {
    ["baz"] = true,
    ["foobaz"] = true,
    ["barbaz"] = true,
    ["bazbaz"] = false,
    ["foo"] = false,
  },
  ["(a|ab)*"] = {
    [""] = true,
    ["a"] = true,
    ["ab"] = true,
    ["aaab"] = true,
    ["aba"] = true,
    ["b"] = false,
  },
  ["(a|b)*c"] = {
    ["c"] = true,
    ["ac"] = true,
    ["bc"] = true,
    ["aabbc"] = true,
    ["d"] = false,
    ["ab"] = false,
  },
  ["a{2,4}"] = {
    ["a"] = false,
    ["aa"] = true,
    ["aaa"] = true,
    ["aaaa"] = true,
    ["aaaaa"] = false,
  },
  ["(ab|cd){2,3}"] = {
    ["abcd"] = true,
    ["abcdab"] = true,
    ["abcdabcd"] = true,
    ["ab"] = false,
    ["abcdabcdcd"] = false,
  },
}

-- Additions to tests
tests["^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+%.[A-Za-z]{2,}$"] = {
  ["test@example.com"] = true,
  ["user.name+tag@domain.co.uk"] = true,
  ["foo@bar"] = false,
  ["@nouser.com"] = false,
  ["plainaddress"] = false,
}

tests["^%d%d%d%-%d%d%-%d%d%d%d$"] = { -- SSN: ###-##-####
  ["123-45-6789"] = true,
  ["000-00-0000"] = true,
  ["12-345-6789"] = false,
  ["123456789"] = false,
  ["abc-de-ghij"] = false,
}

tests["^%(%d%d%d%)%s?%d%d%d%-%d%d%d%d$"] = { -- US phone: (###) ###-####
  ["(123) 456-7890"] = true,
  ["(987)654-3210"] = true,
  ["123-456-7890"] = false,
  ["(12) 345-6789"] = false,
  ["(123)4567890"] = false,
}

tests["^https?://[A-Za-z0-9.-]+%.[A-Za-z]{2,}(/.*)?$"] = { -- URL (basic)
  ["http://example.com"] = true,
  ["https://sub.domain.org/path/to/page"] = true,
  ["ftp://example.com"] = false,
  ["example.com"] = false,
  ["http:/bad.com"] = false,
}

tests["^[0-9]{5}(-[0-9]{4})?$"] = { -- US ZIP code
  ["12345"] = true,
  ["12345-6789"] = true,
  ["1234"] = false,
  ["123456"] = false,
  ["ABCDE"] = false,
}

tests["^[A-Fa-f0-9]{2}(:[A-Fa-f0-9]{2}){5}$"] = { -- MAC address
  ["00:1A:2B:3C:4D:5E"] = true,
  ["ff:ff:ff:ff:ff:ff"] = true,
  ["01:23:45:67:89"] = false,
  ["GG:HH:II:JJ:KK:LL"] = false,
}

tests["^[0-9A-Fa-f]{8}$"] = { -- Hexadecimal hash stub
  ["DEADBEEF"] = true,
  ["deadbeef"] = true,
  ["1234567"] = false,
  ["123456789"] = false,
  ["nothex!!"] = false,
}

-- 1. Hexadecimal validation
tests["^[0-9A-Fa-f]{8}$"] = {
  ["DEADBEEF"] = true,
  ["deadbeef"] = true,
  ["1234567"] = false,
  ["123456789"] = false,
  ["nothex!!"] = false,
}

-- 2. Email address (simplified real-world)
tests["^[A-Za-z0-9._%%+-]+@[A-Za-z0-9.-]+%.[A-Za-z]{2,}$"] = {
  ["user@example.com"] = true,
  ["test.email+alex@leetcode.com"] = true,
  ["user@localserver"] = false,
  ["user@.com"] = false,
  ["@nouser.com"] = false,
}

-- 3. IPv4 address
tests["^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(%.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)){3}$"] = {
  ["192.168.1.1"] = true,
  ["255.255.255.255"] = true,
  ["999.999.999.999"] = false,
  ["1.2.3"] = false,
}

-- 4. Date (YYYY-MM-DD)
tests["^%d%d%d%d%-%d%d%-%d%d$"] = {
  ["2024-01-30"] = true,
  ["99-01-01"] = false,
  ["2024/01/30"] = false,
}

-- 5. URL (simplified)
tests["^https?://[%w-_%.%?%.:/%+=&]+$"] = {
  ["https://example.com"] = true,
  ["http://test.org/page?id=5"] = true,
  ["ftp://nothttp.com"] = false,
  ["example.com"] = false,
}

-- 6. US phone number
tests["^%(%d%d%d%)%s?%d%d%d%-%d%d%d%d$"] = {
  ["(555) 123-4567"] = true,
  ["(123)456-7890"] = true,
  ["555-1234"] = false,
}

-- 7. UUID (8-4-4-4-12)
tests["^[0-9a-fA-F]{8}%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"] = {
  ["123e4567-e89b-12d3-a456-426614174000"] = true,
  ["baduuid-1234"] = false,
}

-- 8. Floating-point numbers
tests["^[+-]?%d*%.?%d+$"] = {
  ["12.34"] = true,
  ["-0.001"] = true,
  ["3."] = true,
  [".25"] = true,
  ["abc"] = false,
}

-- 9. Password (at least 8 chars, 1 upper, 1 lower, 1 digit)
tests["^(?=.*[a-z])(?=.*[A-Z])(?=.*%d).{8,}$"] = {
  ["Password1"] = true,
  ["weakpass"] = false,
  ["STRONG1"] = false,
}

-- 10. File extension matcher (e.g. .png, .jpg)
tests["^.+%.[Pp][Nn][GgJj][Pp][Ee]*[Gg]$"] = {
  ["image.png"] = true,
  ["photo.JPG"] = true,
  ["archive.zip"] = false,
}

-- 11. HTML tag (simple)
tests["^<([A-Za-z]+)([^<]+)*(?:>(.*)</%1>|/>)$"] = {
  ["<div>content</div>"] = true,
  ["<img src='x'/>"] = true,
  ["<notclosed>"] = false,
}

-- 12. Time (HH:MM 24-hour)
tests["^(2[0-3]|[01]%d):[0-5]%d$"] = {
  ["00:00"] = true,
  ["23:59"] = true,
  ["24:00"] = false,
  ["12:60"] = false,
}

-- 13. MAC address
tests["^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$"] = {
  ["00:1A:2B:3C:4D:5E"] = true,
  ["GG:HH:II:JJ:KK:LL"] = false,
}

-- 14. Slug (e.g. blog/my-post-123)
tests["^[a-z0-9]+(?:%-[a-z0-9]+)*$"] = {
  ["my-post-123"] = true,
  ["Invalid_Slug"] = false,
  ["also--bad"] = false,
}

-- 15. Balanced parentheses (simple, not recursive)
tests["^[^%(%)]+%([^%(%)]+%)[^%(%)]+$"] = {
  ["abc(def)ghi"] = true,
  ["no brackets"] = false,
  ["((nested))"] = false,
}

local fails = 0
local compFails = 0
local incorrect = 0
local passes = 0
local total = 0

for pattern, cases in pairs(tests) do
  -- tokenize → parse → compile
  local ast = nil
  pcall(function() ast = sDFA.utils.parse(pattern) end)
  local nfa = nil
  pcall(function() nfa = sDFA.utils.compile(ast, sDFA) end)

  if not nfa or not ast then
    print("\x1b[1;31m" .. "[COMPILER FAILURE]" .. "\x1b[1;0m", pattern, "failed to compile")
  end

  for input, expected in pairs(cases) do
    total = total + 1
    if not nfa or not ast then
      compFails = compFails + 1
      break
    end
    local result = nil
    local r, s = pcall(function() result = sDFA.run(nfa, input) end)

    if result == expected then
      print("\x1b[1;32m" .. "[PASS]" .. "\x1b[1;0m", input, pattern, "expected:", expected, "got:", result)
      passes = passes + 1
    elseif result == false then
      print("\x1b[1;33m" .. "[INCORRECT]" .. "\x1b[1;0m", input, pattern, "expected:", expected, "got:", result)
      incorrect = incorrect + 1
    else
      print("\x1b[1;31m" .. "[FAILURE]" .. "\x1b[1;0m", input, pattern, "expected:", expected, "got:", result)
      fails = fails + 1
    end
  end
end

local pass_rate = (passes / total) * 100
local incorrect_rate = (incorrect / total) * 100
local fail_rate = (fails / total) * 100
local compFail_rate = (compFails / total) * 100

print(" ")
print(" ")
print(" ")
print("---------------------------------------------")
print(" Test Results")
print("\x1b[1;36m" .. " Total  ", total)
print("\x1b[1;32m" .. " Passes ", passes, math.floor(pass_rate) .. "%")
print("\x1b[1;33m" .. " Incorrect ", incorrect, math.floor(incorrect_rate) .. "%")
print("\x1b[1;31m" .. " Failures ", fails, math.floor(fail_rate) .. "%")
print("\x1b[1;31m" .. " Compfails ", compFails, math.floor(compFail_rate) .. "%")
print("\x1b[1;0m" .. "---------------------------------------------")
