-- A bunch of generic utility functions

local function strSplit(delim,str)
    local t = {}
    for substr in string.gmatch(str, "[^".. delim.. "]*") do
        if substr ~= nil and string.len(substr) > 0 then
            table.insert(t,substr)
        end
    end
    return t
  end
  
  local function starts_with(str, start)
    return str:sub(1, #start) == start
  end
  
  local function ends_with(str, ending)
    return ending == "" or str:sub(-#ending) == ending
  end

  local function GetDateAndTimeString()
    return zo_strformat("<<1>> <<2>>", GetDateStringFromTimestamp(GetTimeStamp()), GetTimeString())
  end

  