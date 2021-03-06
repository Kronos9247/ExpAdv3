--[[
	   ____      _  _      ___    ___       ____      ___      ___     __     ____      _  _          _        ___     _  _       ____
	  F ___J    FJ  LJ    F _ ", F _ ",    F ___J    F __".   F __".   FJ    F __ ]    F L L]        /.\      F __".  FJ  L]     F___ J
	 J |___:    J \/ F   J `-' |J `-'(|   J |___:   J (___|  J (___|  J  L  J |--| L  J   \| L      //_\\    J |--\ LJ |  | L    `-__| L
	 | _____|   /    \   |  __/F|  _  L   | _____|  J\___ \  J\___ \  |  |  | |  | |  | |\   |     / ___ \   | |  J |J J  F L     |__  (
	 F L____:  /  /\  \  F |__/ F |_\  L  F L____: .--___) \.--___) \ F  J  F L__J J  F L\\  J    / L___J \  F L__J |J\ \/ /F  .-____] J
	J________LJ__//\\__LJ__|   J__| \\__LJ________LJ\______JJ\______JJ____LJ\______/FJ__L \\__L  J__L   J__LJ______/F \\__//   J\______/F
	|________||__/  \__||__L   |__|  J__||________| J______F J______F|____| J______F |__L  J__|  |__L   J__||______F   \__/     J______F

	::Compiler::
]]

local string_Explode = string.Explode;
local string_upper = string.upper;
local string_format = string.format;
local table_concat = table.concat;

E3Class = EXPR_LIB.GetClass;

local function name(id)
	local obj = E3Class(id);
	return obj and obj.name or id;
end

local function names(ids)
	if (isstring(ids)) then
		ids = string_Explode(",", ids);
	end

	local names = {};

	for i, id in pairs(ids) do
		local obj = E3Class(id);
		names[i] =  obj and obj.name or id;
	end

	return table_concat(names,", ")
end

--[[
]]

local COMPILER = {};
COMPILER.__index = COMPILER;

function COMPILER.New()
	return setmetatable({}, COMPILER);
end

function COMPILER.Initialize(this, instance, files)
	this.__tokens = instance.tokens;
	this.__tasks = instance.tasks;
	this.__root = instance.instruction;
	this.__script = instance.script;
	this.__directives = instance.directives;

	this.__scope = {};
	this.__scopeID = 0;
	this.__scopeData = {};
	this.__scopeData[0] = this.__scope;

	this.__scope.memory = {};
	this.__scope.classes = {};
	this.__scope.interfaces = {};
	this.__scope.server = true;
	this.__scope.client = true;

	this.__defined = {};

	this.__constructors = {};
	this.__operators = {};
	this.__functions = {};
	this.__methods = {};
	this.__enviroment = {};
	this.__hashtable = {};

	this.__files = files;
end

function COMPILER.Run(this)
	--TODO: PcallX for stack traces on internal errors?
	local status, result = pcall(this._Run, this);

	if (status) then
		return true, result;
	end

	if (type(result) == "table") then
		return false, result;
	end

	local err = {};
	err.state = "internal";
	err.msg = result;

	return false, err;
end

function COMPILER._Run(this)
	this:SetOption("state", EXPR_SHARED);

	this:Compile(this.__root);

	local result = {}
	result.script = this.__script;
	result.constructors = this.__constructors;
	result.operators = this.__operators;
	result.functions = this.__functions;
	result.methods = this.__methods;
	result.enviroment = this.__enviroment;
	result.directives = this.__directives;
	result.hashTable = this.__hashtable;

	result.build = function()
		local script, traceTbl = this:BuildScript();
		result.compiled = script;
		result.traceTbl = traceTbl;
	end

	return result;
end

local function sortGth(a, b)
	return (a.weight or a.depth or 0) > (a.weight or a.depth or 0);
end


local function sortLth(a, b)
	return (a.weight or a.depth or 0) < (a.weight or a.depth or 0);
end



function COMPILER.BuildScript(this)
	-- This will probably become a separate stage (post compiler?).

	local buffer = {};
	local alltasks = this.__tasks;

	local off = 0;
	local char = 0;
	local line = -0;
	local traceTable = {};

	for k, v in pairs(this.__tokens) do
		local data = tostring(v.data);

		if (v.newLine) then
			char = 1;
			line = line + 1;
			buffer[#buffer + 1] = "\n";
		end

		local tasks = alltasks[v.pos];

		if (tasks) then
			local callbacks = tasks.callbacks;

			if (callbacks) then
				for _, callback in pairs(callbacks) do
					callback.fun(unpack(callback.args));
				end
			end

			local prefixs = tasks.prefix;

			if (prefixs) then
				table.sort(prefixs, sortGth);
				for _, prefix in pairs(prefixs) do
					if (prefix.newLine) then
						char = 1;
						off = off + 1;
						line = line + 1;
						buffer[#buffer + 1] = "\n";
					end

					local str = prefix.str;

					char = char + #str + 1;

					buffer[#buffer + 1] = str;

					print("PREFIX", str);
				end
			end

			if (not tasks.remove) then
				if (tasks.replace) then
					buffer[#buffer + 1] = tasks.replace.str;
					char = char + #tasks.replace;
					print("REPLACE", tasks.replace.str);
				else
					buffer[#buffer + 1] = data;
					char = char + #data + 1;
					print("KEEP", data);
				end

				traceTable[#traceTable + 1] = {e3_line = v.line - 1, e3_char = v.char, native_line = line, native_char = char, instruction = tasks.instruction};
			end

			local postfixs = tasks.postfix;

			if (postfixs) then
				table.sort(postfixs, sortLth);
				for _, postfix in pairs(postfixs) do
					if (postfix.newLine) then
						char = 1;
						off = off + 1;
						line = line + 1;
						buffer[#buffer + 1] = "\n";
					end
					local str = postfix.str; -- .. string.format("(%s)", postfix.weight or postfix.depth or 0)
					char = char + #str + 1;
					buffer[#buffer + 1] = str;
					print("POSTFIX", data);
				end
			end
		else
			traceTable[#traceTable + 1] = {e3_line = v.line - 1, e3_char = v.char, native_line = line, native_char = char};
			buffer[#buffer + 1] = data;
			char = char + #data + 1;
			print("KEEP", data);
		end
	end

	return table_concat(buffer, " "), traceTable;
end

function COMPILER.Throw(this, token, msg, fst, ...)
	local err = {};

	if (fst) then
		msg = string_format(msg, fst, ...);
	end

	err.state = "compiler";
	err.char = token.char;
	err.line = token.line;
	err.msg = msg;

	error(err,0);
end

--[[
]]

function COMPILER.OffsetToken(this, token, offset)
	local pos = token.index + offset;

	local token = this.__tokens[pos];

	return token;
end

--[[
]]

function COMPILER.Import(this, path)
	local g = _G;
	local e = this.__enviroment;
	local a = string_Explode(".", path);

	if (#a > 1) then
		for i = 1, #a - 1 do
			local k = a[i];
			local v = g[k];

			if (istable(v)) then
				if (not istable(e[k])) then
					e[k] = {};
				end

				g = v;
				e = e[k];
			end
		end
	end

	local k = a[#a];
	local v = g[k];

	if(isfunction(v)) then
		e[k] = v;
	end
end

--[[
]]
function COMPILER.CRC(this, start, final)
	local i, tokens = 0, {};

	for j = start.index, final.index do
		i = i + 1;
		tokens[i] = this.__tokens[j].data;
	end

	return util.CRC(table_concat(tokens, " "));
end

--[[
]]

function COMPILER.PushScope(this)
	this.__scope = {};
	this.__scope.memory = {};
	this.__scope.classes = {};
	this.__scope.interfaces = {};
	this.__scopeID = this.__scopeID + 1;
	this.__scopeData[this.__scopeID] = this.__scope;
end

function COMPILER.PopScope(this)
	this.__scopeData[this.__scopeID] = nil;
	this.__scopeID = this.__scopeID - 1;
	this.__scope = this.__scopeData[this.__scopeID];
end

function COMPILER.SetOption(this, option, value, deep)
	if (not deep) then
		this.__scope[option] = value;
	else
		for i = this.__scopeID, 0, -1 do
			local v = this.__scopeData[i][option];

			if (v) then
				this.__scopeData[i][option] = value;
				break;
			end
		end
	end
end

function COMPILER.GetOption(this, option, nonDeep)
	if (this.__scope[option] ~= nil) then
		return this.__scope[option];
	end

	if (not nonDeep) then
		for i = this.__scopeID, 0, -1 do
			local v = this.__scopeData[i][option];

			if (v ~= nil) then
				return v;
			end
		end
	end
end

function COMPILER.SetVariable(this, name, class, scope)
	if (not scope) then
		scope = this.__scopeID;
	end

	local var = {};
	var.name = name;
	var.class = class;
	var.scope = scope;
	this.__scopeData[scope].memory[name] = var;

	return class, scope, var;
end

function COMPILER.GetVariable(this, name, scope, nonDeep)
	if (not scope) then
		scope = this.__scopeID;
	end

	local v = this.__scopeData[scope].memory[name];

	if (v) then
		return v.class, v.scope, v;
	end

	if (not nonDeep) then
		for i = scope, 0, -1 do
			local v = this.__scopeData[i].memory[name];

			if (v) then
				return v.class, v.scope, v;
			end
		end
	end
end

local bannedVars = {
	["GLOBAL"] = true,
	["SERVER"] = true,
	["CLIENT"] = true,
	["CONTEXT"] = true,
	["_OPS"] = true,
	["_CONST"] = true,
	["_METH"] = true,
	["_FUN"] = true,
	["invoke"] = true,
	["in"] = true,
	["if"] = true,
	["then"] = true,
	["end"] = true,
	["pairs"] = true,
};

function COMPILER.AssignVariable(this, token, declaired, varName, class, scope)
	if (bannedVars[varName]) then
		this:Throw(token, "Unable to declare variable %s, name is reserved internally.", varName);
	end

	if (not scope) then
		scope = this.__scopeID;
	end

	local c, s, var = this:GetVariable(varName, scope, declaired);

	if (declaired) then
		if (c and c == class) then
			this:Throw(token, "Unable to declare variable %s, Variable already exists.", varName);
		elseif (c and class ~= "") then
			this:Throw(token, "Unable to Initialize variable %s, %s expected got %s.", varName, name(c), name(class));
		else
			return this:SetVariable(varName, class, scope);
		end
	else
		if (not c) then
			this:Throw(token, "Unable to assign variable %s, Variable doesn't exist.", varName);
		elseif (c ~= class and class ~= "") then
			this:Throw(token, "Unable to assign variable %s, %s expected got %s.", varName, name(c), name(class));
		end
	end

	return c, s, var;
end

--[[
]]

function COMPILER.GetOperator(this, operation, fst, ...)
	if (not fst) then
		return EXPR_OPERATORS[operation .. "()"];
	end

	local signature = string_format("%s(%s)", operation, table_concat({fst, ...},","));

	local Op = EXPR_OPERATORS[signature];

	if (Op) then
		return Op;
	end

	-- TODO: Inheritance.
end

--[[
]]

function COMPILER.QueueCallBack(this, inst, token, fun, ...)

	local op = {};
	op.token = token;
	op.inst = inst;
	op.fun = fun;
	op.args = {...};

	local tasks = this.__tasks[token.pos];

	if (not tasks) then
		tasks = {};
		this.__tasks[token.pos] = tasks;
	end

	callbacks = tasks.callbacks;

	if (not callbacks) then
		callbacks = {};
		tasks.callbacks = callbacks;
	end

	callbacks[#callbacks + 1] = op;

	return op;
end

function COMPILER.QueueReplace(this, inst, token, str)

	local op = {};
	op.token = token;
	op.str = str;
	op.inst = inst;
	op.deph = inst.stmt_deph or 0;

	local tasks = this.__tasks[token.pos];

	if (not tasks) then
		tasks = {};
		this.__tasks[token.pos] = tasks;
	end

	tasks.replace = op;

	return op;
end

function COMPILER.QueueRemove(this, inst, token)

	if (!token) then debug.Trace() end
	local op = {};

	op.token = token;
	op.inst = inst;
	op.deph = inst.stmt_deph or 0;

	local tasks = this.__tasks[token.pos];

	if (not tasks) then
		tasks = {};
		this.__tasks[token.pos] = tasks;
	end

	tasks.remove = op;

	return op;
end

local injectNewLine = false;

function COMPILER.QueueInjectionBefore(this, inst, token, str, ...)

	local tasks = this.__tasks[token.pos];

	if (not tasks) then
		tasks = {};
		this.__tasks[token.pos] = tasks;
	end

	if (not tasks.prefix) then
		tasks.prefix = {};
	end

	local r = {};
	local t = {str, ...};

	for i = 1, #t do
		local op = {};

		op.token = token;
		op.str = t[i];
		op.inst = inst;
		op.deph = inst.stmt_deph or 0;

		if (i == 1) then
			op.newLine = injectNewLine;
		end

		tasks.prefix[#tasks.prefix + 1] = op;
	end

	return r;
end

function COMPILER.QueueInjectionAfter(this, inst, token, str, ...)
	local op = {};

	op.token = token;
	op.str = str;
	op.inst = inst;
	op.deph = inst.stmt_deph or 0;

	local tasks = this.__tasks[token.pos];

	if (not tasks) then
		tasks = {};
		this.__tasks[token.pos] = tasks;
	end

	if (not tasks.postfix) then
		tasks.postfix = {};
	end

	local r = {};
	local t = {str, ...};

	for i = 1, #t do
		local op = {};

		op.token = token;
		op.str = t[i];
		op.inst = inst;
		op.deph = inst.stmt_deph or 0;

		if (i == 1) then
			op.newLine = injectNewLine;
		end

		r[#r + 1] = op;
		tasks.postfix[#tasks.postfix + 1] = op;
	end

	return r;
end

--[[
]]

function COMPILER.QueueInstruction(this, inst, inst, token, inst, type)
	local op = {};
	op.token = token;
	op.inst = inst;
	op.type = type;
	op.deph = inst.stmt_deph or 0;

	local tasks = this.__tasks[token.pos];

	if (not tasks) then
		tasks = {};
		this.__tasks[token.pos] = tasks;
	end

	if (not tasks.instruction) then
		tasks.instruction = op;
	end

	return op;
end

function COMPILER.Compile(this, inst)
	if (not inst) then
		debug.Trace();
		error("Compiler was asked to compile a nil instruction.")
	end

	if (not istable(inst.token)) then
		debug.Trace();
		print("token is ", type(inst.token), inst.token);
	end

	if (not inst.compiled) then
		local instruction = string_upper(inst.type);
		local fun = this["Compile_" .. instruction];

		-- print("Compiler->" .. instruction .. "->#" .. #inst.instructions)

		if (not fun) then
			this:Throw(inst.token, "Failed to compile unknown instruction %s", instruction);
		end

		--this:QueueInstruction(inst, inst.token, inst.type);

		local type, count = fun(this, inst, inst.token, inst.instructions);

		if (type) then
			inst.result = type;
			inst.rCount = count or 1;
		end

		inst.compiled = true;
	end

	return inst.result, inst.rCount;
end

--[[
]]


--[[
]]

function COMPILER.Compile_ROOT(this, inst, token, stmts)
	injectNewLine = true;
		this:QueueInjectionBefore(inst, token, "return", "function", "(", "env", ")");
		this:QueueInjectionBefore(inst, token, "setfenv", "(", "1", ",", "env", ")");
		this:QueueInjectionBefore(inst, token, "");
	injectNewLine = false;

	for i = 1, #stmts do
		this:Compile(stmts[i]);
	end

	injectNewLine = true;
		this:QueueInjectionAfter(inst, inst.final, "end");
	injectNewLine = false;

	return "", 0;
end

function COMPILER.Compile_SEQ(this, inst, token, stmts)
	for i = 1, #stmts do
		this:Compile(stmts[i]);
	end

	return "", 0;
end

function COMPILER.Compile_IF(this, inst, token)
	local r, c = this:Compile(inst.condition);

	if (class ~= "b") then
		local isBool = this:Expression_IS(inst.condition);

		if (not isBool) then
			local t = this:CastExpression("b", inst.condition);

			if (not t) then
				this:Throw(token, "Type of %s can not be used as a condition.", name(r));
			end
		end
	end

	this:PushScope();

	this:Compile(inst.block);

	this:PopScope();

	if (inst._else) then
		this:Compile(inst._else);
	end

	return "", 0;
end

function COMPILER.Compile_ELSEIF(this, inst, token)
	local class, count = this:Compile(inst.condition);

	if (class ~= "b") then
		local isBool = this:Expression_IS(inst.condition);

		if (not isBool) then
			local t = this:CastExpression("b", inst.condition);

			if (not t) then
				this:Throw(token, "Type of %s can not be used as a condition.", name(r));
			end
		end
	end

	this:PushScope();

	this:Compile(inst.block);

	this:PopScope();

	if (inst._else) then
		this:Compile(inst._else);
	end

	return "", 0;
end

function COMPILER.Compile_ELSE(this, inst, token)
	this:PushScope();

	this:Compile(inst.block);

	this:PopScope();

	return "", 0;
end

--[[
]]

function COMPILER.CheckState(this, state, token, msg, frst, ...)
	local s = this:GetOption("state");

	if (state == EXPR_SHARED or s == state) then
		return true;
	end

	if (token and msg) then
		if (frst) then
			msg = string_format(msg, frst, ...);
		end

		if (state == EXPR_SERVER) then
			this:Throw(token, "%s is server-side only.", msg);
		elseif (state == EXPR_SERVER) then
			this:Throw(token, "%s is client-side only.", msg);
		end
	end

	return false;
end

function COMPILER.Compile_SERVER(this, inst, token)
	if (not this:GetOption("server")) then
		this:Throw(token, "Server block must not appear inside a Client block.")
	end

	this:PushScope();
	this:SetOption("state", EXPR_SERVER);
	this:Compile(inst.block);

	this:PopScope();

	return "", 0;
end

function COMPILER.Compile_CLIENT(this, inst, token)
	if (not this:GetOption("client")) then
		this:Throw(token, "Client block must not appear inside a Server block.")
	end

	this:PushScope();
	this:SetOption("state", EXPR_CLIENT);
	this:Compile(inst.block);

	this:PopScope();

	return "", 0;
end

--[[
]]

function COMPILER.Compile_GLOBAL(this, inst, token, expressions)
	local tArgs = #expressions;

	local results = {};

	for i = 1, tArgs do
		local arg = expressions[i];
		local r, c = this:Compile(arg);

		if (not inst.variables[i]) then
			this:Throw(arg.token, "Unable to assign here, value #%i has no matching variable.", i);
		elseif (i < tArgs) then
			results[#results + 1] = {r, arg, true};
		else
			for j = 1, c do
				results[#results + 1] = {r, arg, j == 1};
			end
		end
	end

	for i = 1, #inst.variables do
		local result = results[i];
		local token = inst.variables[i];
		local var = token.data;

		if (not result) then
			this:Throw(token, "Unable to assign variable %s, no matching value.", var);
		end

		local class, scope, info = this:AssignVariable(token, true, var, inst.class, 0);

		if (info) then
			info.global = true;
			info.prefix = "GLOBAL";
			this:QueueReplace(inst, token, info.prefix .. "." .. var);
		end

		this.__defined[var] = true;

		if (result[1] ~= inst.class) then
			local casted = false;
			local arg = result[2];

			if (result[3]) then
				-- TODO: CAST
			end

			if (not casted) then
				this:AssignVariable(arg.token, true, var, result[1], 0);
			end
		end
	end

	this.__defined = {};

	return "", 0;
end

function COMPILER.Compile_LOCAL(this, inst, token, expressions)
	local tArgs = #expressions;

	local results = {};

	for i = 1, tArgs do
		local arg = expressions[i];
		local r, c = this:Compile(arg);

		if (not inst.variables[i]) then
			this:Throw(arg.token, "Unable to assign here, value #%i has no matching variable.", i);
		elseif (i < tArgs) then
			results[#results + 1] = {r, arg, true};
		else
			for j = 1, c do
				results[#results + 1] = {r, arg, j == 1};
			end
		end
	end

	for i = 1, #inst.variables do
		local result = results[i];
		local token = inst.variables[i];
		local var = token.data;

		if (not result) then
			this:Throw(token, "Unable to assign variable %s, no matching value.", var);
		end

		local class, scope, info = this:AssignVariable(token, true, var, inst.class);

		this.__defined[var] = true;

		if (result[1] ~= inst.class and result[1] ~= "") then
			local casted = false;
			local arg = result[2];

			if (result[3]) then
				-- TODO: CAST
			end

			if (not casted) then
				this:AssignVariable(arg.token, false, var, result[1]);
			end
		end
	end

	this.__defined = {};

	return "", 0;
end

function COMPILER.Compile_ASS(this, inst, token, expressions)
	local tArgs = #expressions;

	local results = {};

	for i = 1, tArgs do
		local arg = expressions[i];
		local r, c = this:Compile(arg);

		if (not inst.variables[i]) then
			this:Throw(arg.token, "Unable to assign here, value #%i has no matching variable.", i);
		elseif (i < tArgs) then
			results[#results + 1] = {r, arg, true};
		else
			for j = 1, c do
				results[#results + 1] = {r, arg, j == 1};
			end
		end
	end

	for i = 1, #inst.variables do
		local result = results[i];

		local token = inst.variables[i];
		local var = token.data;

		if (not result) then
			this:Throw(token, "Unable to assign variable %s, no matching value.", var);
		end

		this.__defined[var] = true;

		local type = result[1];
		local class, scope, info = this:GetVariable(var);

		if (type ~= class) then
			local arg = result[2];

			if (result[3]) then
				-- TODO: CAST
				-- Once done rember: type = class;
			end
		end

		local class, scope, info = this:AssignVariable(token, false, var, class);

		if (info and info.prefix) then
			var = info.prefix .. "." .. var;

			this:QueueReplace(inst, token, var);
		end

		if (inst.class == "f") then
			injectNewLine = true;

			if (info.signature) then
				local msg = string_format("Failed to assign function to delegate %s(%s), permater missmatch.", var, info.signature);
				this:QueueInjectionAfter(inst, inst.final, string_format("if (%s and %s.signature ~= %q) then CONTEXT:Throw(%q); %s = nil; end", var, var, info.signature, msg, var));
			end

			if (info.resultClass) then
				local msg = string_format("Failed to assign function to delegate %s(%s), result type missmatch.", var, name(info.resultClass));
				this:QueueInjectionAfter(inst, inst.final, string_format("if (%s and %s.result ~= %q) then CONTEXT:Throw(%q); %s = nil; end", var, var, name(info.resultClass), msg, var));
			end

			if (info.resultCount) then
				local msg = string_format("Failed to assign function to delegate %s(%s), result count missmatch.", var, info.resultCount);
				this:QueueInjectionAfter(inst, inst.final, string_format("if (%s and %s.count ~= %i) then CONTEXT:Throw(%q); %s = nil; end", var, var, info.resultCount, msg, var));
			end

			injectNewLine = false;
		end
	end

	this.__defined = {};

	return "", 0;
end

--[[
]]

function COMPILER.Compile_AADD(this, inst, token, expressions)
	this:QueueReplace(inst, inst.__operator, "=");

	for k = 1, #inst.variables do
		local token = inst.variables[k];
		local expr = expressions[k];
		local r, c = this:Compile(expr);

		local class, scope, info = this:GetVariable(token.data, nil, false);

		if (info and info.prefix) then
			this:QueueReplace(inst, token, info.prefix .. "." .. token.data);
		end

		local char = "+";

		local op = this:GetOperator("add", class, r);

		if (not op and r ~= class) then
			if (this:CastExpression(class, expr)) then
				op = this:GetOperator("add", class, class);
			end
		end

		if (not op) then
			this:Throw(expr.token, "Assignment operator (+=) does not support '%s += %s'", name(class), name(r));
		end

		this:CheckState(op.state, token, "Assignment operator (+=)");

		if (not op.operator) then
			if (r == "s" or class == "s") then
				char = "..";
			end

			if (info and info.prefix) then
				this:QueueInjectionBefore(inst, expr.token, info.prefix .. "." .. token.data, char);
			else
				this:QueueInjectionBefore(inst, expr.token, token.data, char);
			end
		else
			-- Implement Operator
			this.__operators[op.signature] = op.operator;

			this:QueueInjectionBefore(inst, expr.token, "_OPS", "[", "\"" .. op.signature .. "\"", "]", "(");

			if (op.context) then
			    this:QueueInjectionBefore(inst, expr.token, "CONTEXT", ",");
			end

			this:QueueInjectionAfter(inst, expr.final, ")" );
		end

		this:AssignVariable(token, false, token.data, op.result);
	end
end

function COMPILER.Compile_ASUB(this, inst, token, expressions)
	this:QueueReplace(inst, inst.__operator, "=");

	for k = 1, #inst.variables do
		local token = inst.variables[k];
		local expr = expressions[k];
		local r, c = this:Compile(expr);

		local class, scope, info = this:GetVariable(token.data, nil, false);

		if (info and info.prefix) then
			this:QueueInjectionBefore(inst, token, info.prefix .. ".");
		end

		local op = this:GetOperator("sub", class, r);

		if (not op and r ~= class) then
			if (this:CastExpression(class, expr)) then
				op = this:GetOperator("sub", class, class);
			end
		end

		if (not op) then
			this:Throw(expr.token, "Assignment operator (-=) does not support '%s -= %s'", name(class), name(r));
		end

		this:CheckState(op.state, token, "Assignment operator (-=)");

		if (not op.operator) then
			if (info and info.prefix) then
				this:QueueInjectionBefore(inst, expr.token, info.prefix .. "." .. token.data, "-");
			else
				this:QueueInjectionBefore(inst, expr.token, token.data, char);
			end
		else
			-- Implement Operator
			this.__operators[op.signature] = op.operator;

			this:QueueInjectionBefore(inst, expr.token, "_OPS", "[", "\"" .. op.signature .. "\"", "]", "(");

			if (op.context) then
			    this:QueueInjectionBefore(inst, expr.token, "CONTEXT", ",");
			end

			this:QueueInjectionAfter(inst, expr.final, ")" );
		end

		this:AssignVariable(token, false, token.data, op.result);
	end
end



function COMPILER.Compile_ADIV(this, inst, token, expressions)
	this:QueueReplace(inst, inst.__operator, "=");

	for k = 1, #inst.variables do
		local token = inst.variables[k];
		local expr = expressions[k];
		local r, c = this:Compile(expr);

		local class, scope, info = this:GetVariable(token.data, nil, false);

		if (info and info.prefix) then
			this:QueueInjectionBefore(inst, token, info.prefix .. ".");
		end

		local op = this:GetOperator("div", class, r);

		if (not op and r ~= class) then
			if (this:CastExpression(class, expr)) then
				op = this:GetOperator("div", class, class);
			end
		end

		if (not op) then
			this:Throw(expr.token, "Assignment operator (/=) does not support '%s /= %s'", name(class), name(r));
		end

		this:CheckState(op.state, token, "Assignment operator (/=)");

		if (not op.operator) then
			if (info and info.prefix) then
				this:QueueInjectionBefore(inst, expr.token, info.prefix .. "." .. token.data, "/");
			else
				this:QueueInjectionBefore(inst, expr.token, token.data, char);
			end
		else
			-- Implement Operator
			this.__operators[op.signature] = op.operator;

			this:QueueInjectionBefore(inst, expr.token, "_OPS", "[", "\"" .. op.signature .. "\"", "]", "(");

			if (op.context) then
			    this:QueueInjectionBefore(inst, expr.token, "CONTEXT", ",");
			end

			this:QueueInjectionAfter(inst, expr.final, ")" );
		end

		this:AssignVariable(token, false, token.data, op.result);
	end
end

function COMPILER.Compile_AMUL(this, inst, token, expressions)
	this:QueueReplace(inst, inst.__operator, "=");

	for k = 1, #inst.variables do
		local token = inst.variables[k];
		local expr = expressions[k];
		local r, c = this:Compile(expr);

		local class, scope, info = this:GetVariable(token.data, nil, false);

		if (info and info.prefix) then
			this:QueueInjectionBefore(inst, token, info.prefix .. ".");
		end

		local op = this:GetOperator("mul", class, r);

		if (not op and r ~= class) then
			if (this:CastExpression(class, expr)) then
				op = this:GetOperator("mul", class, class);
			end
		end

		if (not op) then
			this:Throw(expr.token, "Assignment operator (*=) does not support '%s *= %s'", name(class), name(r));
		end

		this:CheckState(op.state, token, "Assignment operator (*=)");

		if (not op.operator) then
			if (info and info.prefix) then
				this:QueueInjectionBefore(inst, expr.token, info.prefix .. "." .. token.data, "*");
			else
				this:QueueInjectionBefore(inst, expr.token, token.data, char);
			end
		else
			-- Implement Operator
			this.__operators[op.signature] = op.operator;

			this:QueueInjectionBefore(inst, expr.token, "_OPS", "[", "\"" .. op.signature .. "\"", "]", "(");

			if (op.context) then
			    this:QueueInjectionBefore(inst, expr.token, "CONTEXT", ",");
			end

			this:QueueInjectionAfter(inst, expr.final, ")" );
		end

		this:AssignVariable(token, false, token.data, op.result);
	end
end

--[[
]]

function COMPILER.Compile_GROUP(this, inst, token, expr)

	local pre = this:OffsetToken(token, -1);
	local next = this:OffsetToken(inst.final, 1);

	if (pre and next) then
		if (pre.type == "lpa" and next.type == "rpa") then
			return r, c;
		end
	end

	this:QueueInjectionBefore(inst, token, "(");
	this:QueueInjectionAfter(inst, inst.final, ")");

	local r, c = this:Compile(expr);

	return r, c;
end

function COMPILER.Compile_TEN(this, inst, token, expressions)
	local expr1 = expressions[1];
	local r1, c1 = this:Compile(expr1);

	local expr2 = expressions[2];
	local r2, c2 = this:Compile(expr2);

	local expr3 = expressions[3];
	local r3, c3 = this:Compile(expr3);

	local op = this:GetOperator("ten", r1, r2, r3);

	if (not op) then
		this:Throw(expr.token, "Tenary operator (A ? B : C) does not support '%s ? %s : %s'", name(r1), name(r2), name(r3));
	elseif (not op.operator) then
		this:QueueReplace(inst, inst.__and, "and");
		this:QueueReplace(inst, inst.__or, "or");
	else
		this:QueueInjectionBefore(inst, expr1.token, "_OPS[\"" .. op.signature .. "\"](");

		if (op.context) then
		    this:QueueInjectionBefore(inst, expr1.token, "CONTEXT", ",");
		end

		this:QueueReplace(inst, inst.__and, ",");
		this:QueueReplace(inst, inst.__or, ",");

		this:QueueInjectionAfter(inst, expr3.final, ")" );

		this.__operators[op.signature] = op.operator;
	end

	this:CheckState(op.state, token, "Tenary operator (A ? B : C)");

	return op.result, op.rCount;
end


function COMPILER.Compile_OR(this, inst, token, expressions)
	local expr1 = expressions[1];
	local r1, c1 = this:Compile(expr1);

	local expr2 = expressions[2];
	local r2, c2 = this:Compile(expr2);

	local op = this:GetOperator("or", r1, r2);

	if (not op) then
		local is1 = this:Expression_IS(expr1);
		local is2 = this:Expression_IS(expr2);

		if (is1 and is2) then
			op = this:GetOperator("and", "b", "b");
		end

		if (not op) then
			this:Throw(token, "Logical or operator (||) does not support '%s || %s'", name(r1), name(r2));
		end
	elseif (not op.operator) then
		this:QueueReplace(inst, inst.__operator, "or");
	else
		this:QueueInjectionBefore(inst, expr1.token, "_OPS[\"" .. op.signature .. "\"](");

		if (op.context) then
		    this:QueueInjectionBefore(inst, expr1.token, "CONTEXT", ",");
		end

		this:QueueReplace(inst, inst.__operator, ",");

		this:QueueInjectionAfter(inst, expr2.final, ")" );

		this.__operators[op.signature] = op.operator;
	end

	this:CheckState(op.state, token, "Logical or operator (||) '%s || %s'", name(r1), name(r2));

	return op.result, op.rCount;
end

function COMPILER.Compile_AND(this, inst, token, expressions)
	local expr1 = expressions[1];
	local r1, c1 = this:Compile(expr1);

	local expr2 = expressions[2];
	local r2, c2 = this:Compile(expr2);

	local op = this:GetOperator("and", r1, r2);

	if (not op) then
		local is1 = this:Expression_IS(expr1);
		local is2 = this:Expression_IS(expr2);

		if (is1 and is2) then
			op = this:GetOperator("and", "b", "b");
		end

		if (not op) then
			this:Throw(token, "Logical and operator (&&) does not support '%s && %s'", name(r1), name(r2));
		end
	elseif (not op.operator) then
		this:QueueReplace(inst, inst.__operator, "and");
	else
		this:QueueInjectionBefore(inst, expr1.token, "_OPS[\"" .. op.signature .. "\"](");

		if (op.context) then
		    this:QueueInjectionBefore(inst, expr1.token, "CONTEXT", ",");
		end

		this:QueueReplace(inst, inst.__operator, ",");

		this:QueueInjectionAfter(inst, expr2.final, ")" );

		this.__operators[op.signature] = op.operator;
	end

	this:CheckState(op.state, token, "Logical and operator (&&) '%s && %s'", name(r1), name(r2));

	return op.result, op.rCount;
end

function COMPILER.Compile_BXOR(this, inst, token, expressions)
	local expr1 = expressions[1];
	local r1, c1 = this:Compile(expr1);

	local expr2 = expressions[2];
	local r2, c2 = this:Compile(expr2);

	local op = this:GetOperator("bxor", r1, r2);

	if (not op) then
		this:Throw(token, "Binary xor operator (^^) does not support '%s ^^ %s'", name(r1), name(r2));
	elseif (not op.operator) then
		this:QueueInjectionBefore(inst, expr1.token, "bit.bxor(");

		this:QueueReplace(inst, inst.__operator, ",");

		this:QueueInjectionAfter(inst, expr2.final, ")" );


	else
		this:QueueInjectionBefore(inst, expr1.token, "_OPS[\"" .. op.signature .. "\"](");

		if (op.context) then
		    this:QueueInjectionBefore(inst, expr1.token, "CONTEXT", ",");
		end

		this:QueueReplace(inst, inst.__operator, ",");

		this:QueueInjectionAfter(inst, expr2.final, ")" );

		this.__operators[op.signature] = op.operator;
	end

	this:CheckState(op.state, token, "Binary xor operator (^^) '%s ^^ %s'", name(r1), name(r2));

	return op.result, op.rCount;
end

function COMPILER.Compile_BOR(this, inst, token, expressions)
	local expr1 = expressions[1];
	local r1, c1 = this:Compile(expr1);

	local expr2 = expressions[2];
	local r2, c2 = this:Compile(expr2);

	local op = this:GetOperator("bor", r1, r2);

	if (not op) then
		this:Throw(token, "Binary or operator (|) does not support '%s | %s'", name(r1), name(r2));
	elseif (not op.operator) then
		this:QueueInjectionBefore(inst, expr1.token, "bit.bor(");

		this:QueueReplace(inst, inst.__operator, ",");

		this:QueueInjectionAfter(inst, expr2.final, ")" );

	else
		this:QueueInjectionBefore(inst, expr1.token, "_OPS[\"" .. op.signature .. "\"](");

		if (op.context) then
		    this:QueueInjectionBefore(inst, expr1.token, "CONTEXT", ",");
		end

		this:QueueReplace(inst, inst.__operator, ",");

		this:QueueInjectionAfter(inst, expr2.final, ")" );

		this.__operators[op.signature] = op.operator;
	end

	this:CheckState(op.state, token, "Binary xor operator (|) '%s | %s'", name(r1), name(r2));

	return op.result, op.rCount;
end

function COMPILER.Compile_BAND(this, inst, token, expressions)
	local expr1 = expressions[1];
	local r1, c1 = this:Compile(expr1);

	local expr2 = expressions[2];
	local r2, c2 = this:Compile(expr2);

	local op = this:GetOperator("band", r1, r2);

	if (not op) then
		this:Throw(token, "Binary or operator (&) does not support '%s & %s'", name(r1), name(r2));
	elseif (not op.operator) then
		this:QueueInjectionBefore(inst, expr1.token, "bit.band(");

		this:QueueReplace(inst, inst.__operator, ",");

		this:QueueInjectionAfter(inst, expr2.final, ")" );


	else
		this:QueueInjectionBefore(inst, expr1.token, "_OPS[\"" .. op.signature .. "\"](");

		if (op.context) then
		    this:QueueInjectionBefore(inst, expr1.token, "CONTEXT", ",");
		end

		this:QueueReplace(inst, inst.__operator, ",");

		this:QueueInjectionAfter(inst, expr2.final, ")" );

		this.__operators[op.signature] = op.operator;
	end

	this:CheckState(op.state, token, "Binary xor operator (&) '%s & %s'", name(r1), name(r2));

	return op.result, op.rCount;
end

--[[function COMPILER.Compile_EQ_MUL(inst, token, expressions)
end]]

function COMPILER.Compile_EQ(this, inst, token, expressions)
	local expr1 = expressions[1];
	local r1, c1 = this:Compile(expr1);

	local expr2 = expressions[2];
	local r2, c2 = this:Compile(expr2);

	local op = this:GetOperator("eq", r1, r2);

	if (not op) then
		this:Throw(token, "Comparison operator (==) does not support '%s == %s'", name(r1), name(r2));
	elseif (not op.operator) then
		-- Leave the code alone.
	else
		this:QueueInjectionBefore(inst, expr1.token, "_OPS[\"" .. op.signature .. "\"](");

		if (op.context) then
		    this:QueueInjectionBefore(inst, expr1.token, "CONTEXT", ",");
		end

		this:QueueReplace(inst, inst.__operator, ",");

		this:QueueInjectionAfter(inst, expr2.final, ")" );

		this.__operators[op.signature] = op.operator;
	end

	this:CheckState(op.state, token, "Comparison operator (==) '%s == %s'", name(r1), name(r2));

	return op.result, op.rCount;
end

--[[function COMPILER.Compile_NEQ_MUL(inst, token, expressions)
end]]

function COMPILER.Compile_NEQ(this, inst, token, expressions)
	local expr1 = expressions[1];
	local r1, c1 = this:Compile(expr1);

	local expr2 = expressions[2];
	local r2, c2 = this:Compile(expr2);

	local op = this:GetOperator("neq", r1, r2);

	if (not op) then
		this:Throw(token, "Comparison operator (!=) does not support '%s != %s'", name(r1), name(r2));
	elseif (not op.operator) then
		this:QueueReplace(inst, inst.__operator, "~=");
	else
		this:QueueInjectionBefore(inst, expr1.token, "_OPS[\"" .. op.signature .. "\"](");

		if (op.context) then
		    this:QueueInjectionBefore(inst, expr1.token, "CONTEXT", ",");
		end

		this:QueueReplace(inst, inst.__operator, ",");

		this:QueueInjectionAfter(inst, expr2.final, ")" );

		this.__operators[op.signature] = op.operator;
	end

	this:CheckState(op.state, token, "Comparison operator (!=) '%s != %s'", name(r1), name(r2));

	return op.result, op.rCount;
end

function COMPILER.Compile_LTH(this, inst, token, expressions)
	local expr1 = expressions[1];
	local r1, c1 = this:Compile(expr1);

	local expr2 = expressions[2];
	local r2, c2 = this:Compile(expr2);

	local op = this:GetOperator("lth", r1, r2);

	if (not op) then
		this:Throw(token, "Comparison operator (<) does not support '%s < %s'", name(r1), name(r2));
	elseif (not op.operator) then
		-- Leave the code alone.
	else
		this:QueueInjectionBefore(inst, expr1.token, "_OPS[\"" .. op.signature .. "\"](");

		if (op.context) then
		    this:QueueInjectionBefore(inst, expr1.token, "CONTEXT", ",");
		end

		this:QueueReplace(inst, inst.__operator, ",");

		this:QueueInjectionAfter(inst, expr2.final, ")" );

		this.__operators[op.signature] = op.operator;
	end

	this:CheckState(op.state, token, "Comparison operator (<) '%s < %s'", name(r1), name(r2));

	return op.result, op.rCount;
end

function COMPILER.Compile_LEQ(this, inst, token, expressions)
	local expr1 = expressions[1];
	local r1, c1 = this:Compile(expr1);

	local expr2 = expressions[2];
	local r2, c2 = this:Compile(expr2);

	local op = this:GetOperator("leg", r1, r2);

	if (not op) then
		this:Throw(token, "Comparison operator (<=) does not support '%s <= %s'", name(r1), name(r2));
	elseif (not op.operator) then
		-- Leave the code alone.
	else
		this:QueueInjectionBefore(inst, expr1.token, "_OPS[\"" .. op.signature .. "\"](");

		if (op.context) then
		    this:QueueInjectionBefore(inst, expr1.token, "CONTEXT", ",");
		end

		this:QueueReplace(inst, inst.__operator, ",");

		this:QueueInjectionAfter(inst, expr2.final, ")" );

		this.__operators[op.signature] = op.operator;
	end

	this:CheckState(op.state, token, "Comparison operator (<=) '%s <= %s'", name(r1), name(r2));

	return op.result, op.rCount;
end

function COMPILER.Compile_GTH(this, inst, token, expressions)
	local expr1 = expressions[1];
	local r1, c1 = this:Compile(expr1);

	local expr2 = expressions[2];
	local r2, c2 = this:Compile(expr2);

	local op = this:GetOperator("gth", r1, r2);

	if (not op) then
		this:Throw(token, "Comparison operator (>) does not support '%s > %s'", name(r1), name(r2));
	elseif (not op.operator) then
		-- Leave the code alone.
	else
		this:QueueInjectionBefore(inst, expr1.token, "_OPS[\"" .. op.signature .. "\"](");

		if (op.context) then
		    this:QueueInjectionBefore(inst, expr1.token, "CONTEXT", ",");
		end

		this:QueueReplace(inst, inst.__operator, ",");

		this:QueueInjectionAfter(inst, expr2.final, ")" );

		this.__operators[op.signature] = op.operator;
	end

	this:CheckState(op.state, token, "Comparison operator (>) '%s > %s'", name(r1), name(r2));

	return op.result, op.rCount;
end

function COMPILER.Compile_GEQ(this, inst, token, expressions)
	local expr1 = expressions[1];
	local r1, c1 = this:Compile(expr1);

	local expr2 = expressions[2];
	local r2, c2 = this:Compile(expr2);

	local op = this:GetOperator("geq", r1, r2);

	if (not op) then
		this:Throw(token, "Comparison operator (>=) does not support '%s >= %s'", name(r1), name(r2));
	elseif (not op.operator) then
		-- Leave the code alone.
	else
		this:QueueInjectionBefore(inst, expr1.token, "_OPS[\"" .. op.signature .. "\"](");

		if (op.context) then
		    this:QueueInjectionBefore(inst, expr1.token, "CONTEXT", ",");
		end

		this:QueueReplace(inst, inst.__operator, ",");

		this:QueueInjectionAfter(inst, expr2.final, ")" );

		this.__operators[op.signature] = op.operator;
	end

	this:CheckState(op.state, token, "Comparison operator (>=) '%s >= %s'", name(r1), name(r2));

	return op.result, op.rCount;
end

function COMPILER.Compile_BSHL(this, inst, token, expressions)
	local expr1 = expressions[1];
	local r1, c1 = this:Compile(expr1);

	local expr2 = expressions[2];
	local r2, c2 = this:Compile(expr2);

	local op = this:GetOperator("bshl", r1, r2);

	if (not op) then
		this:Throw(token, "Binary shift operator (<<) does not support '%s << %s'", name(r1), name(r2));
	elseif (not op.operator) then
		this:QueueInjectionBefore(inst, expr1.token, "bit.lshift(");

		this:QueueReplace(inst, inst.__operator, ",");

		this:QueueInjectionAfter(inst, expr2.final, ")" );


	else
		this:QueueInjectionBefore(inst, expr1.token, "_OPS[\"" .. op.signature .. "\"](");

		if (op.context) then
		    this:QueueInjectionBefore(inst, expr1.token, "CONTEXT", ",");
		end

		this:QueueReplace(inst, inst.__operator, ",");

		this:QueueInjectionAfter(inst, expr2.final, ")" );

		this.__operators[op.signature] = op.operator;
	end

	this:CheckState(op.state, token, "Binary shift operator (<<) '%s << %s'", name(r1), name(r2));

	return op.result, op.rCount;
end

function COMPILER.Compile_BSHR(this, inst, token, expressions)
	local expr1 = expressions[1];
	local r1, c1 = this:Compile(expr1);

	local expr2 = expressions[2];
	local r2, c2 = this:Compile(expr2);

	local op = this:GetOperator("bshr", r1, r2);

	if (not op) then
		this:Throw(token, "Binary shift operator (>>) does not support '%s >> %s'", name(r1), name(r2));
	elseif (not op.operator) then
		this:QueueInjectionBefore(inst, expr1.token, "bit.rshift(");

		this:QueueReplace(inst, inst.__operator, ",");

		this:QueueInjectionAfter(inst, expr2.final, ")" );


	else
		this:QueueInjectionBefore(inst, expr1.token, "_OPS[\"" .. op.signature .. "\"](");

		if (op.context) then
		    this:QueueInjectionBefore(inst, expr1.token, "CONTEXT", ",");
		end

		this:QueueReplace(inst, inst.__operator, ",");

		this:QueueInjectionAfter(inst, expr2.final, ")" );

		this.__operators[op.signature] = op.operator;
	end

	this:CheckState(op.state, token, "Binary shift operator (>>) '%s >> %s'", name(r1), name(r2));

	return op.result, op.rCount;
end

--[[
]]

function COMPILER.Compile_ADD(this, inst, token, expressions)
	local expr1 = expressions[1];
	local r1, c1 = this:Compile(expr1);

	local expr2 = expressions[2];
	local r2, c2 = this:Compile(expr2);

	local op = this:GetOperator("add", r1, r2);

	if (not op) then
		this:Throw(token, "Addition operator (+) does not support '%s + %s'", name(r1), name(r2));
	elseif (not op.operator) then
		if (r1 == "s" or r2 == "s") then
			this:QueueReplace(inst, inst.__operator, ".."); -- Replace + with .. for string addition;
		end
	else
		this:QueueInjectionBefore(inst, expr1.token, "_OPS[\"" .. op.signature .. "\"](");

		if (op.context) then
		    this:QueueInjectionBefore(inst, expr1.token, "CONTEXT", ",");
		end

		this:QueueReplace(inst, inst.__operator, ",");

		this:QueueInjectionAfter(inst, expr2.final, ")" );

		this.__operators[op.signature] = op.operator;
	end

	this:CheckState(op.state, token, "Addition operator (+) '%s + %s'", name(r1), name(r2));

	return op.result, op.rCount;
end

function COMPILER.Compile_SUB(this, inst, token, expressions)
	local expr1 = expressions[1];
	local r1, c1 = this:Compile(expr1);

	local expr2 = expressions[2];
	local r2, c2 = this:Compile(expr2);

	local op = this:GetOperator("sub", r1, r2);

	if (not op) then
		this:Throw(token, "Subtraction operator (-) does not support '%s - %s'", name(r1), name(r2));
	elseif (not op.operator) then
		-- Do not change the code.
	else
		this:QueueInjectionBefore(inst, expr1.token, "_OPS[\"" .. op.signature .. "\"](");

		if (op.context) then
		    this:QueueInjectionBefore(inst, expr1.token, "CONTEXT", ",");
		end

		this:QueueReplace(inst, inst.__operator, ",");

		this:QueueInjectionAfter(inst, expr2.final, ")" );

		this.__operators[op.signature] = op.operator;
	end

	this:CheckState(op.state, token, "Subtraction operator (-) '%s - %s'", name(r1), name(r2));

	return op.result, op.rCount;
end

function COMPILER.Compile_DIV(this, inst, token, expressions)
	local expr1 = expressions[1];
	local r1, c1 = this:Compile(expr1);

	local expr2 = expressions[2];
	local r2, c2 = this:Compile(expr2);

	local op = this:GetOperator("div", r1, r2);

	if (not op) then
		this:Throw(expr.token, "Division operator (/) does not support '%s / %s'", name(r1), name(r2));
	elseif (not op.operator) then
		-- Do not change the code.
	else
		this:QueueInjectionBefore(inst, expr1.token, "_OPS[\"" .. op.signature .. "\"](");

		if (op.context) then
		    this:QueueInjectionBefore(inst, expr1.token, "CONTEXT", ",");
		end

		this:QueueReplace(inst, inst.__operator, ",");

		this:QueueInjectionAfter(inst, expr2.final, ")" );

		this.__operators[op.signature] = op.operator;
	end

	this:CheckState(op.state, token, "Division operator (/) '%s / %s'", name(r1), name(r2));

	return op.result, op.rCount;
end

function COMPILER.Compile_MUL(this, inst, token, expressions)
	local expr1 = expressions[1];
	local r1, c1 = this:Compile(expr1);

	local expr2 = expressions[2];
	local r2, c2 = this:Compile(expr2);

	local op = this:GetOperator("mul", r1, r2);

	if (not op) then
		this:Throw(token, "Multiplication operator (*) does not support '%s * %s'", name(r1), name(r2));
	elseif (not op.operator) then
		-- Do not change the code.
	else
		this:QueueInjectionBefore(inst, expr1.token, "_OPS[\"" .. op.signature .. "\"](");

		if (op.context) then
		    this:QueueInjectionBefore(inst, expr1.token, "CONTEXT", ",");
		end

		this:QueueReplace(inst, inst.__operator, ",");

		this:QueueInjectionAfter(inst, expr2.final, ")" );

		this.__operators[op.signature] = op.operator;
	end

	this:CheckState(op.state, token, "Multiplication operator (*) '%s * %s'", name(r1), name(r2));

	return op.result, op.rCount;
end

function COMPILER.Compile_EXP(this, inst, token, expressions)
	local expr1 = expressions[1];
	local r1, c1 = this:Compile(expr1);

	local expr2 = expressions[2];
	local r2, c2 = this:Compile(expr2);

	local op = this:GetOperator("exp", r1, r2);

	if (not op) then
		this:Throw(token, "Exponent operator (^) does not support '%s ^ %s'", name(r1), name(r2));
	elseif (not op.operator) then
		-- Do not change the code.
	else
		this:QueueInjectionBefore(inst, expr1.token, "_OPS[\"" .. op.signature .. "\"](");

		if (op.context) then
		    this:QueueInjectionBefore(inst, expr1.token, "CONTEXT", ",");
		end

		this:QueueReplace(inst, inst.__operator, ",");

		this:QueueInjectionAfter(inst, expr2.final, ")" );

		this.__operators[op.signature] = op.operator;
	end

	this:CheckState(op.state, token, "Exponent operator (^) '%s ^ %s'", name(r1), name(r2));

	return op.result, op.rCount;
end

function COMPILER.Compile_MOD(this, inst, token, expressions)
	local expr1 = expressions[1];
	local r1, c1 = this:Compile(expr1);

	local expr2 = expressions[2];
	local r2, c2 = this:Compile(expr2);

	local op = this:GetOperator("mod", r1, r2);

	if (not op) then
		this:Throw(token, "Modulus operator (%) does not support '%s % %s'", name(r1), name(r2));
	elseif (not op.operator) then
		-- Do not change the code.
	else
		this:QueueInjectionBefore(inst, expr1.token, "_OPS[\"" .. op.signature .. "\"](");

		if (op.context) then
		    this:QueueInjectionBefore(inst, expr1.token, "CONTEXT", ",");
		end

		this:QueueReplace(inst, inst.__operator, ",");

		this:QueueInjectionAfter(inst, expr2.final, ")" );

		this.__operators[op.signature] = op.operator;
	end

	this:CheckState(op.state, token, "Modulus operator (%) '%s % %s'", name(r1), name(r2));

	return op.result, op.rCount;
end

function COMPILER.Compile_NEG(this, inst, token, expressions)
	local expr1 = expressions[1];
	local r1, c1 = this:Compile(expr1);

	local op = this:GetOperator("neg", r1);

	if (not op) then
		this:Throw(token, "Negation operator (-A) does not support '-%s'", name(r1));
	elseif (not op.operator) then
		-- Do not change the code.
	else
		this:QueueInjectionBefore(inst, expr1.token, "_OPS[\"" .. op.signature .. "\"](");

		if (op.context) then
		    this:QueueInjectionBefore(inst, expr1.token, "CONTEXT", ",");
		end

		this:QueueInjectionAfter(inst, expr1.final, ")" );

		this.__operators[op.signature] = op.operator;
	end

	this:CheckState(op.state, token, "Negation operator (-A) '-%s'", name(r1));

	return op.result, op.rCount;
end

function COMPILER.Compile_NOT(this, inst, token, expressions)
	local expr1 = expressions[1];
	local r1, c1 = this:Compile(expr1);

	local op = this:GetOperator("not", r1);

	if (not op) then
		this:Throw(token, "Not operator (!A) does not support '!%s'", name(r1), name(r2));
	elseif (not op.operator) then
		this:QueueReplace(inst, inst.__operator, "not");
	else
		this:QueueInjectionBefore(inst, expr1.token, "_OPS[\"" .. op.signature .. "\"](");

		if (op.context) then
		    this:QueueInjectionBefore(inst, expr1.token, "CONTEXT", ",");
		end

		this:QueueInjectionAfter(inst, expr1.final, ")" );

		this.__operators[op.signature] = op.operator;
	end

	this:CheckState(op.state, token, "Not operator (!A) '!%s'", name(r1));

	return op.result, op.rCount;
end

function COMPILER.Compile_LEN(this, inst, token, expressions)
	local expr1 = expressions[1];
	local r1, c1 = this:Compile(expr1);

	local op = this:GetOperator("len", r1);

	if (not op) then
		this:Throw(token, "Length operator (#A) does not support '#%s'", name(r1), name(r2));
	elseif (not op.operator) then
		-- Once again we change nothing.
	else
		this:QueueInjectionBefore(inst, expr1.token, "_OPS[\"" .. op.signature .. "\"](");

		if (op.context) then
		    this:QueueInjectionBefore(inst, expr1.token, "CONTEXT", ",");
		end

		this:QueueInjectionAfter(inst, expr1.final, ")" );

		this.__operators[op.signature] = op.operator;
	end

	this:CheckState(op.state, token, "Length operator (#A) '#%s'", name(r1));

	return op.result, op.rCount;
end

function COMPILER.Compile_DELTA(this, inst, token, expressions)
	local var = inst.__var.data;

	if (this.__defined[var]) then
		this:Throw(token, "Variable %s is defined here and can not be used as part of an expression.", var);
	end

	local c, s, info = this:GetVariable(var);

	if (not c) then
		this:Throw(token, "Variable %s does not exist.", var);
	end

	if (not info.global) then
		this:Throw(token, "Delta operator ($) can not be used on none global variable %s.", var);
	end

	if (info and info.prefix) then
		this:QueueReplace(inst, inst.__var, info.prefix .. "." .. var);
	end

	local op = this:GetOperator("sub", c, c);

	if (not op) then
		this:Throw(token, "Delta operator ($) does not support '$%s'", name(c));
	elseif (not op.operator) then
		this:QueueRemove(inst, inst.__operator);
		this:QueueInjectionBefore(inst, inst.__var, "DELTA", ".", var, "-");
	else
		this:QueueRemove(inst, inst.__operator);
		this:QueueInjectionBefore(inst, inst.__var, "_OPS[\"" .. op.signature .. "\"](");

		if (op.context) then
		    this:QueueInjectionBefore(inst, inst.__var, "CONTEXT", ",", "DELTA", ".", var, ",");
		end

		this:QueueInjectionAfter(inst, inst.__var, ")" );

		this.__operators[op.signature] = op.operator;
	end

	this:CheckState(op.state, token, "Delta operator ($) '$%s'", name(c));

	return op.result, op.rCount;
end

function COMPILER.Compile_CHANGED(this, inst, token, expressions)
	local var = inst.__var.data;

	if (this.__defined[var]) then
		this:Throw(token, "Variable %s is defined here and can not be used as part of an expression.", var);
	end

	local c, s, info = this:GetVariable(var);

	if (not c) then
		this:Throw(token, "Variable %s does not exist.", var);
	end

	if (not info.global) then
		this:Throw(token, "Changed operator (~) can not be used on none global variable %s.", var);
	end

	if (info and info.prefix) then
		this:QueueReplace(inst, inst.__var, info.prefix .. "." .. var);
	end

	local op = this:GetOperator("neq", c, c);

	if (not op) then
		this:Throw(token, "Changed operator (~) does not support '~%s'", name(c));
	elseif (not op.operator) then
		this:QueueRemove(inst, inst.__operator);
		this:QueueInjectionBefore(inst, inst.__var, "DELTA", ".", var, "~=");
	else
		this:QueueRemove(inst, inst.__operator);
		this:QueueInjectionBefore(inst, inst.__var, "_OPS[\"" .. op.signature .. "\"](");

		if (op.context) then
		    this:QueueInjectionBefore(inst, inst.__var, "CONTEXT", ",", "DELTA", ".", var, ",");
		end

		this:QueueInjectionAfter(inst, inst.__var, ")" );

		this.__operators[op.signature] = op.operator;
	end

	this:CheckState(op.state, token, "Changed operator (~) '~%s'", name(c));

	return op.result, op.rCount;
end

function COMPILER.Expression_IS(this, expr)
	local op = this:GetOperator("is", expr.result);

	if (op) then
		if (not this:CheckState(op.state)) then
			return false, expr;
		elseif (not op.operator) then
			expr.result = op.type;
			expr.rCount = op.count;

			return true, expr;
		else
			this:QueueInjectionBefore(inst, expr.token, "_OPS[\"" .. op.signature .. "\"](");

			if (op.context) then
			    this:QueueInjectionBefore(inst, expr.token, "CONTEXT", ",");
			end

			this:QueueInjectionAfter(inst, expr.final, ")" );

			this.__operators[op.signature] = op.operator;

			expr.result = op.type;
			expr.rCount = op.count;

			return true, expr;
		end
	elseif (expr.result == "b") then
		return true, expr;
	end

	return false, expr;
end

function COMPILER.Compile_IOF(this, inst, token, expr)
	local r, c = this:Compile(expr);

	local userclass = this:GetClassOrInterface(inst.__cls.data);

	if (not userclass or not this:GetClassOrInterface(r)) then
		this:Throw(token, "Instanceof currently only supports user classes, sorry about that :D");
	end

	this:QueueRemove(inst, inst.__cls);
	this:QueueRemove(inst, inst.__iof);

	this:QueueInjectionBefore(inst, expr.token,"CheckHash('" .. userclass.hash .. "',");
	this:QueueInjectionAfter(inst, expr.final,")");

	return "b", 1;
end

function COMPILER.CastUserType(this, left, right)
	local to = this:GetClassOrInterface(left);
	local from = this:GetClassOrInterface(right);

	if (not (to or from)) then return end;

	if (not this.__hashtable[to.hash][from.hash]) then
		if (this.__hashtable[from.hash][to.hash]) then
			return {
				signature = string_format("(%s)%s", to.hash, from.hash),
				context = true,
				result = left,
				rCount = 1,
				operator = function(ctx, obj)
					if (not ctx.env.CheckHash(to.hash, obj)) then
						ctx:Throw("Failed to cast %s to %s, #class missmatched.", name(right), name(left));
					end; return obj;
				end,
			};
		end

		return nil;
	end

	return {
		result = left,
		rCount = 1,
	};
	-- hashtable[extends][class] = is isinstance of.
end

function COMPILER.CastExpression(this, type, expr)

	local op = this:CastUserType(type, expr.result);

	if (not op) then
		local signature = string_format("(%s)%s", type, expr.result);

		op = EXPR_CAST_OPERATORS[signature];

		if (not op) then
			return false, expr;
		end

		if (not this:CheckState(op.state)) then
			return false, expr;
		end
	end

	if (op.operator) then
		this:QueueInjectionBefore(inst, expr.token, "_OPS[\"" .. op.signature .. "\"](");

		if (op.context) then
		    this:QueueInjectionBefore(inst, expr.token, "CONTEXT", ",");
		end

		this:QueueInjectionAfter(inst, expr.final, ")" );

		this.__operators[op.signature] = op.operator;
	end

	expr.result = op.result;
	expr.rCount = op.rCount;

	return true, expr;
end

function COMPILER.Compile_CAST(this, inst, token, expressions)
	local expr = expressions[1];

	this:Compile(expr);

	local t = this:CastExpression(inst.class, expr);

	if (not t) then
		this:Throw(token, "Type of %s can not be cast to type of %s.", name(expr.result), name(inst.class))
	end

	return expr.result, expr.rCount;
end

function COMPILER.Compile_VAR(this, inst, token, expressions)
	if (this.__defined[inst.variable]) then
		this:Throw(token, "Variable %s is defined here and can not be used as part of an expression.", inst.variable);
	end

	local c, s, var = this:GetVariable(inst.variable)

	if (var and var.prefix) then
		local prefix = var.atribute and ("this." .. var.prefix) or var.prefix;
		this:QueueReplace(inst, token, prefix .. "." .. token.data);
	end

	if (not c) then
		this:Throw(token, "Variable %s does not exist.", inst.variable);
	end

	return c, 1;
end

function COMPILER.Compile_BOOL(this, inst, token, expressions)
	return "b", 1
end

function COMPILER.Compile_NUM(this, inst, token, expressions)
	return "n", 1
end

function COMPILER.Compile_STR(this, inst, token, expressions)
	return "s", 1
end

function COMPILER.Compile_PTRN(this, inst, token, expressions)
	return "_ptr", 1
end

function COMPILER.Compile_CLS(this, inst, token, expressions)
	this:QueueReplace(inst, token, "\"" .. token.data .. "\"");
	return "_cls", 1
end

function COMPILER.Compile_NIL(this, inst, token, expressions)
	this:QueueReplace(inst, token, "NIL");
	return "", 1
end

function COMPILER.Compile_COND(this, inst, token, expressions)
	local expr = expressions[1];
	local r, c = this:Compile(expr);

	if (r == "b") then
		return r, c;
	end

	local op = this:GetOperator("is", r);

	if (not op and this:CastExpression("b", expr)) then
		return r, "b";
	end

	if (not op) then
		this:Throw(token, "No such condition (%s).", name(r));
	elseif (not op.operator) then
		-- Once again we change nothing.
	else
		this:QueueInjectionBefore(inst, expr.token, "_OPS[\"" .. op.signature .. "\"](");

		if (op.context) then
		    this:QueueInjectionBefore(inst, expr.token, "CONTEXT", ",");
		end

		this:QueueInjectionAfter(inst, expr.final, ")" );

		this.__operators[op.signature] = op.operator;
	end

	return op.result, op.rCount;
end

function COMPILER.Compile_NEW(this, inst, token, expressions)
	local op;
	local ids = {};
	local total = #expressions;

	local classname = inst.class
	local cls = E3Class(classname);
	local userclass = this:GetUserClass(classname);

	if (not cls and userclass) then
		cls = userclass;
		classname = "constructor";
	end

	if (total == 0) then
		op = cls.constructors[classname .. "()"];
	else
		local constructors = cls.constructors;

		for k, expr in pairs(expressions) do
			local r, c = this:Compile(expr);
			ids[#ids + 1] = r;

			if (k == total) then
				if (c > 1) then
					for i = 2, c do
						ids[#ids + 1] = r;
					end
				end
			end
		end

		for i = #ids, 1, -1 do
			local args = table_concat(ids,",", 1, i);

			if (i >= total) then
				local signature = string_format("%s(%s)", classname, args);

				op = constructors[signature];
			end

			if (not op) then
				local signature = string_format("%s(%s,...)", classname, args);
				op = constructors[signature];
				if (op) then vargs = i + 1; end
			end

			if (op) then
				break;
			end
		end

		if (not op) then
			op = constructors[classname .. "(...)"];
			if (op) then vargs = 1; end
		end
	end

	local signature = string_format("%s(%s)", name(inst.class), names(ids));

	if (op and userclass) then
		this:QueueRemove(inst, inst.__new);
		this:QueueInjectionAfter(inst, inst.__const, "['" ..  op .. "']");

		return userclass.name, 1;
	end

	if (not op) then
		this:Throw(token, "No such constructor, new %s", signature);
	end

	this:CheckState(op.state, token, "Constructor 'new %s", signature);

	if (type(op.operator) == "function") then

		this:QueueRemove(inst, inst.__new);
		this:QueueRemove(inst, inst.__const);
		this:QueueRemove(inst, inst.__lpa);

		this:QueueInjectionBefore(inst, inst.__const, "_CONST[\"" .. op.signature .. "\"](");

		if (op.context) then
		    this:QueueInjectionBefore(inst, inst.__const, "CONTEXT");

		    if (total > 0) then
				this:QueueInjectionBefore(inst, inst.__const, ",");
			end
		end

		this.__constructors[op.signature] = op.operator;
	elseif (type(op.operator) == "string") then
		this:QueueRemove(inst, inst.__new);
		this:QueueRemove(inst, inst.__const);
		this:QueueReplace(inst, inst.__const, op.operator);
	else
		local signature = string_format("%s.", inst.library, op.signature);
		error("Attempt to inject " .. op.signature .. " but operator was incorrect " .. type(op.operator) .. ".");
	end

	if (vargs) then
		if (#expressions >= 1) then
			for i = vargs, #expressions do
				local arg = expressions[i];

				if (arg.result ~= "_vr") then -- this was once offset by -1, had issues {"",,v} {"",,v}
					this:QueueInjectionBefore(inst, arg.token, "{", "\"" .. arg.result .. "\"", ",");

					this:QueueInjectionAfter(inst, arg.final, "}");
				end
			end
		end
	end

	return op.result, op.rCount;
end

local function getMethod(mClass, userclass, method, ...)
	local prams = table_concat({...}, ",");

	if (userclass) then
		local sig = string_format("@%s(%s)", method, prams);
		return userclass.methods[sig];
	end

	local sig = string_format("%s.%s(%s)", mClass, method, prams);
	return EXPR_METHODS[sig];
end

function COMPILER.Compile_METH(this, inst, token, expressions)
	local expr = expressions[1];
	local mClass, mCount = this:Compile(expr);

	local op;
	local vargs;
	local ids = {};
	local total = #expressions;

	local userclass = this:GetUserClass(mClass);


	if (total == 1) then
		op = getMethod(mClass, userclass, inst.method);
	else
		for k, expr in pairs(expressions) do
			if (k > 1) then
				local r, c = this:Compile(expr);

				ids[#ids + 1] = r;

				if (k == total) then
					if (c > 1) then
						for i = 2, c do
							ids[#ids + 1] = r;
						end
					end
				end
			end
		end

		for i = #ids, 1, -1 do
			local args = table_concat(ids,",", 1, i);

			if (i == total -  1) then
				op = getMethod(mClass, userclass, inst.method, args);
			end

			if (not op) then
				op = getMethod(mClass, userclass, inst.method, args, "...");

				if (op) then
					vargs = i;
				end
			end

			if (op) then
				break;
			end
		end

		if (not op) then
			op = getMethod(mClass, userclass, inst.method, "...");

			if (op) then
				vargs = 1;
			end
		end
	end

	if (not op) then
		this:Throw(token, "No such method %s.%s(%s).", name(mClass), inst.method, names(ids));
	end

	if (userclass) then
		this:QueueRemove(inst, inst.__lpa);
		this:QueueInjectionBefore(inst, expr.token, userclass.name, "['".. op.sig.. "'](");
		this:QueueReplace(inst, inst.__operator, total > 1 and "," or "");
		this:QueueRemove(inst, inst.__method);
		return op.result, op.count;
	end

	this:CheckState(op.state, token, "Method %s.%s(%s)", name(mClass), inst.method, names(ids));

	if (type(op.operator) == "function") then
		this:QueueRemove(inst, inst.__operator);
		this:QueueRemove(inst, inst.__method);

		if (total == 1) then
			this:QueueRemove(inst, inst.__lpa);
		else
			this:QueueReplace(inst, inst.__lpa, ",");
		end

		this:QueueInjectionBefore(inst, expr.token, "_METH[\"" .. op.signature .. "\"](");

		if (op.context) then
		    this:QueueInjectionBefore(inst, expr.token , "CONTEXT,");
		end

		this.__methods[op.signature] = op.operator;
	elseif (type(op.operator) == "string") then
		this:QueueReplace(inst, inst.__operator, ":");
		this:QueueReplace(inst, inst.__method, op.operator);
	else
		local signature = string_format("%s.%s", name(inst.class), op.signature);
		error("Attempt to inject " .. op.signature .. " but operator was incorrect, got " .. type(op.operator));
	end

	if (vargs) then
		if (#expressions > 1) then
			for i = vargs, #expressions do
				local arg = expressions[i];

				if (arg.result ~= "_vr") then
					this:QueueInjectionBefore(inst, this:OffsetToken(arg.token, -1), "{", "\"" .. arg.result .. "\"", ",");

					this:QueueInjectionAfter(inst, arg.final, "}");
				end
			end
		end
	end

	return op.result, op.rCount;
end

function COMPILER.Compile_FUNC(this, inst, token, expressions)
	local lib = EXPR_LIBRARIES[inst.library.data];

	if (not lib) then
		-- Please note this should be impossible.
		this:Throw(token, "Library %s does not exist.", inst.library.data);
	end

	local op;
	local vargs;
	local ids = {};
	local total = #expressions;

	if (total == 0) then
		op = lib._functions[inst.name .. "()"];
	else
		for k, expr in pairs(expressions) do
			local r, c = this:Compile(expr);

			ids[#ids + 1] = r;

			if (k == total) then
				if (c > 1) then
					for i = 2, c do
						ids[#ids + 1] = r;
					end
				end
			end
		end

		for i = #ids, 1, -1 do
			local args = table_concat(ids,",", 1, i);

			if (i >= total) then
				local signature = string_format("%s(%s)", inst.name, args);

				op = lib._functions[signature];
			end

			if (not op) then
				local signature = string_format("%s(%s,...)", inst.name, args);

				op = lib._functions[signature];

				if (op) then vargs = i + 1 end
			end

			if (op) then
				break;
			end
		end

		if (not op) then
			op = lib._functions[inst.name .. "(...)"];

			if (op) then vargs = 1 end
		end
	end

	if (not op) then
		this:Throw(token, "No such function %s.%s(%s).", inst.library.data, inst.name, names(ids, ","));
	end

	this:CheckState(op.state, token, "Function %s.%s(%s).", inst.library.data, inst.name, names(ids, ","));

	if (type(op.operator) == "function") then
		local signature = string_format("%s.%s", inst.library.data, op.signature);

		this:QueueRemove(inst, token);
		this:QueueRemove(inst, inst.library);
		this:QueueRemove(inst, inst.__operator);
		this:QueueRemove(inst, inst.__func);

		this:QueueInjectionAfter(inst, inst.__func, "_FUN[\"" .. signature .. "\"]");

		if (op.context) then
			this:QueueInjectionAfter(inst, inst.__lpa, "CONTEXT");

		    if (total > 0) then
				this:QueueInjectionAfter(inst, inst.__lpa, ",");
			end
		end

		this.__functions[signature] = op.operator;
	elseif (type(op.operator) == "string") then
		--this:QueueRemove(inst, token);
		this:QueueRemove(inst, inst.library);
		this:QueueRemove(inst, inst.__operator);
		this:QueueReplace(inst, inst.__func, op.operator); -- This is error.
		this:Import(op.operator);
	else
		local signature = string_format("%s.", inst.library, op.signature);
		error("Attempt to inject " .. signature .. " but operator was incorrect " .. type(op.operator) .. ".");
	end

	if (vargs) then
		if (#expressions >= 1) then
			for i = vargs, #expressions do
				local arg = expressions[i];

				if (arg.result ~= "_vr") then
					this:QueueInjectionAfter(inst, this:OffsetToken(arg.token, -1), "{", "\"" .. arg.result .. "\"", ",");

					this:QueueInjectionAfter(inst, arg.final, "}");
				end
			end
		end
	end

	if (inst.library.data == "system") then
		local res, count = hook.Run("Expression3.PostCompile.System." .. inst.name, this, inst, token, expressions);

		if (res and count) then
			return res, count;
		end
	end

	return op.result, op.rCount;
end

--[[
]]

function COMPILER.Compile_LAMBDA(this, inst, token, expressions)
	this:PushScope();

	for _, param in pairs(inst.params) do
		local var = param[2];
		local class = param[1];

		this:AssignVariable(token, true, var, class);

		if (class ~= "_vr") then
			injectNewLine = true;
			this:QueueInjectionBefore(inst, inst.stmts.token, string_format("if (%s == nil or %s[1] == nil) then CONTEXT:Throw(\"%s expected for %s, got void\"); end", var, var, name(class), var));
			this:QueueInjectionBefore(inst, inst.stmts.token, string_format("if (%s[1] ~= %q) then CONTEXT:Throw(\"%s expected for %s, got \" .. %s[1]); end", var, class, name(class), var, var));
			this:QueueInjectionBefore(inst, inst.stmts.token, string_format("%s = %s[2];", var, var));
			injectNewLine = false;
		end
	end

	this:SetOption("udf", (this:GetOption("udf") or 0) + 1);

	this:SetOption("loop", false);
	this:SetOption("canReturn", true);
	this:SetOption("retunClass", "?"); -- Indicate we do not know this yet.
	this:SetOption("retunCount", -1); -- Indicate we do not know this yet.

	this:Compile(inst.stmts);

	local result = this:GetOption("retunClass");
	local count = this:GetOption("retunCount");

	this:PopScope();

	if (result == "?" or count == -1) then
		result = "";
		count = 0;
	end

	this:QueueInjectionAfter(inst, inst.__end, ", result = \"" .. result .. "\"");
	this:QueueInjectionAfter(inst, inst.__end, ", count = " .. count);
	this:QueueInjectionAfter(inst, inst.__end, ", scr = CONTEXT");
	this:QueueInjectionAfter(inst, inst.__end, "}");

	return "f", 1;
end

--[[
]]

function COMPILER.Compile_RETURN(this, inst, token, expressions)
	if (not this:GetOption("canReturn", false)) then
		this:Throw(token, "A return statment can not appear here.");
	end

	local result = this:GetOption("retunClass");
	local count = this:GetOption("retunCount");

	local results = {};

	for _, expr in pairs(expressions) do
		local r, c = this:Compile(expr);
		results[#results + 1] = {r, c};
	end

	local outClass;

	if (result == "?") then
		for i = 1, #results do
			local t = results[i][1];

			if (not outClass) then
				outClass = t;
			elseif (outClass ~= t) then
				outClass = "_vr";
				break;
			end
		end

		this:SetOption("retunClass", outClass or "", true);
	else
		outClass = result;
	end

	local outCount = 0;

	for i = 1, #results do
		local expr = expressions[i];
		local res = results[i][1];
		local cnt = results[i][2];

		if (res ~= outClass) then
			local ok = this:CastExpression(outClass, expr);

			if (not ok) then
				this:Throw(expr.token, "Can not return %s here, %s expected.", name(res), name(outClass));
			end
		end

		if (i < #results) then
			outCount = outCount + 1;
		else
			outCount = outCount + cnt;
		end
	end

	if (count == -1) then
		count = outCount;
		this:SetOption("retunCount", outCount, true);
	end

	if (count ~= outCount) then
		this:Throw(expr.token, "Can not return %i %s('s) here, %i %s('s) expected.", name(outCount), name(outClass), count, name(outClass));
	end
end

function COMPILER.Compile_BREAK(this, inst, token)
	if (not this:GetOption("loop", false)) then
		this:Throw(token, "Break must not appear outside of a loop");
	end
end

function COMPILER.Compile_CONTINUE(this, inst, token)
	if (not this:GetOption("loop", false)) then
		this:Throw(token, "Continue must not appear outside of a loop");
	end
end

--[[
]]

function COMPILER.Compile_DELEGATE(this, inst, token)
	local class, scope, info = this:AssignVariable(token, true, inst.variable, "f");

	if (info) then
		info.signature = table_concat(inst.parameters, ",");
		info.parameters = inst.parameters;
		info.resultClass = inst.resultClass;
		info.resultCount = inst.resultCount;
	end

	injectNewLine = true;
	this:QueueInjectionBefore(inst, token, "local " .. inst.variable)
	injectNewLine = false;
end

function COMPILER.Compile_FUNCT(this, inst, token, expressions)
	this:PushScope();

	for _, param in pairs(inst.params) do
		local var = param[2];
		local class = param[1];

		this:AssignVariable(token, true, var, class);

		if (class ~= "_vr") then
			injectNewLine = true;
			this:QueueInjectionBefore(inst, inst.stmts.token, string_format("if (%s == nil or %s[1] == nil) then CONTEXT:Throw(\"%s expected for %s, got void\"); end", var, var, class, var));
			this:QueueInjectionBefore(inst, inst.stmts.token, string_format("if (%s[1] ~= %q) then CONTEXT:Throw(\"%s expected for %s, got \" .. %s[1]); end", var, class, class, var, var));
			this:QueueInjectionBefore(inst, inst.stmts.token, string_format("%s = %s[2];", var, var));
			injectNewLine = false;
		end
	end

	this:SetOption("loop", false);
	this:SetOption("udf", (this:GetOption("udf") or 0) + 1);

	this:SetOption("canReturn", true);
	this:SetOption("retunClass", inst.resultClass);
	this:SetOption("retunCount", -1); -- Indicate we do not know this yet.

	this:Compile(inst.stmts);

	local count = this:GetOption("retunCount");

	this:PopScope();

	local variable = inst.variable;

	local class, scope, info = this:AssignVariable(token, true, variable, "f");

	if (info) then
		info.signature = inst.signature;
		info.parameters = inst.params;
		info.resultClass = inst.resultClass;
		info.resultCount = count;

		if (info.prefix) then
			variable = info.prefix .. "." .. variable;
		else
			this:QueueInjectionBefore(inst, token, "local");
		end
	end

	this:QueueInjectionBefore(inst, token, variable, " = { op = ");
	this:QueueInjectionAfter(inst, inst.__end, ", signature = \"" .. inst.signature .. "\"");
	this:QueueInjectionAfter(inst, inst.__end, ", result = \"" .. info.resultClass .. "\"");
	this:QueueInjectionAfter(inst, inst.__end, ", count = " .. count);
	this:QueueInjectionAfter(inst, inst.__end, "}");
end

--[[
]]

function COMPILER.Compile_CALL(this, inst, token, expressions)
	local expr = expressions[1];
	local res, count = this:Compile(expr);

	local prms = {};

	if (#expressions > 1) then
		for i = 2, #expressions do
			local arg = expressions[i];
			local r, c = this:Compile(arg);

			prms[#prms + 1] = r;

			if (i == #expressions and c > 1) then
				for j = 2, c do
					prms[#prms + 1] = r;
				end
			end
		end
	end

	local signature = table_concat(prms, ",");

	if (res == "f" and expr.type == "var") then
		local c, s, info = this:GetVariable(expr.variable);
		-- The var instruction will have already validated this variable.

		if (info.signature) then
			if (info.signature ~= signature) then
				this:Throw(token, "Invalid arguments to user function got %s(%s), %s(%s) expected.", expr.variable, names(signature), expr.variable, names(info.signature));
			end

			if (#expressions > 1) then
				for i = 2, #expressions do
					local arg = expressions[i];

					if (arg.result ~= "_vr") then
						this:QueueInjectionBefore(inst, arg.token, "{", "\"" .. arg.result .. "\"", ",");

						this:QueueInjectionAfter(inst, arg.final, "}");
					end
				end
			end

			this:QueueReplace(inst, expr.token, "invoke");

			this:QueueInjectionAfter(inst, token, "(", "CONTEXT", ",\"" .. info.resultClass .. "\",", tostring(info.resultCount), ",");

			if (info.prefix) then
				this:QueueInjectionAfter(inst, token, info.prefix .. "." .. expr.variable);
			else
				this:QueueInjectionAfter(inst, token, expr.variable);
			end

			if (#prms >= 1) then
				this:QueueInjectionAfter(inst, token, ",");
			end

			return info.resultClass, info.resultCount;
		end
	end

	local op;

	if (#prms == 0) then
		op = this:GetOperator("call", res, "");

		if (not op) then
			op = this:GetOperator("call", res, "...");
		end
	else
		for i = #prms, 1, -1 do
			local args = table_concat(prms,",", 1, i);

			if (i >= #prms) then
				op = this:GetOperator("call", res, args);
			end

			if (not op) then
				op = this:GetOperator("call", args, res, "...");
			end

			if (op) then
				break;
			end
		end
	end

	if (not op) then
		this:Throw(token, "No such call operation %s(%s)", name(res), names(prms));
	end

	this:CheckState(op.state, token, "call operation %s(%s).", name(res), names(prms));

	this:QueueRemove(inst, token); -- Removes (

	this:QueueInjectionBefore(inst, expr.token, "_OPS[\"" .. op.signature .. "\"]", "(");

	if (op.context) then
		this:QueueInjectionBefore(inst, expr.token, "CONTEXT", ",");
	end

	if (#prms >= 1) then
		this:QueueInjectionBefore(inst, token, ",");
	end

	this.__operators[op.signature] = op.operator;

	return op.result, op.rCount;
end

--[[
]]

function COMPILER.Compile_GET(this, inst, token, expressions)
	local value = expressions[1];
	local vType = this:Compile(value);
	local index = expressions[2];
	local iType = this:Compile(index);

	local op;
	local keepid = false;
	local cls = inst.class;

	if (not cls) then
		op = this:GetOperator("get", vType, iType);

		if (not op) then
			this:Throw(token, "No such get operation %s[%s]", name(vType), name(iType));
		end
	else
		op = this:GetOperator("get", vType, iType, cls.data);

		if (not op) then
			keepid = true;

			this:QueueReplace(inst, cls, "\'" .. cls.data .. "\'");

			op = this:GetOperator("get", vType, iType, "_cls");

			if (op) then
				if (op.result == "") then
					op.result = cls.data;
					op.rCount = 1;
				end
			end
		end

		if (not op) then
			if cls then
				this:Throw(token, "No such get operation %s[%s,%s]", name(vType), name(iType), name(cls.data));
			else
				this:Throw(token, "No such get operation %s[%s]", name(vType), name(iType));
			end
		end
	end

	this:CheckState(op.state);

	if (not op.operator) then
		return op.result, op.rCount;
	end

	this:QueueInjectionBefore(inst, value.token, "_OPS[\"" .. op.signature .. "\"](");

	if (op.context) then
	   this:QueueInjectionBefore(inst, value.token, "CONTEXT", ",");
	end

	if (cls) then
		if (not keepid) then
			this:QueueRemove(inst, cls);
		else
			this:QueueReplace(inst, cls, "'" .. cls.data .. "'");
		end
	end

	this:QueueReplace(inst, inst.__rsb, ")" );

	this:QueueReplace(inst, inst.__lsb, "," );

	this.__operators[op.signature] = op.operator;

	if (cls) then
		return cls.data, 1;
	end

	return op.result, op.rCount;
end

function COMPILER.Compile_SET(this, inst, token, expressions)
	local value = expressions[1];
	local vType = this:Compile(value);
	local index = expressions[2];
	local iType = this:Compile(index);
	local expr = expressions[3];
	local vExpr = this:Compile(expr);

	local op;
	local keepclass = false;
	local cls = inst.class;

	if (cls and vExpr ~= cls.data) then
		this:Throw(token, "Can not assign %s onto %s, %s expected.", name(vExpr), name(vType), name(cls.data));
	end

	if (not cls) then
		op = this:GetOperator("set", vType, iType, vExpr);
	else
		op = this:GetOperator("set", vType, iType, cls.data);

		if (not op) then
			keepclass = true;
			op = this:GetOperator("set", vType, iType, "_cls", vExpr)
		end
	end

	if (not op) then
		if (not cls) then
			this:Throw(token, "No such set operation %s[%s] = ", name(vType), name(iType), name(vExpr));
		else
			this:Throw(token, "No such set operation %s[%s, %s] = ", name(vType), name(iType), name(cls.data), name(vExpr));
		end
	end

	this:CheckState(op.state);

	if (not op.operator) then
		return op.result, op.rCount;
	end

	this:QueueRemove(inst, inst.__lsb);

	this:QueueInjectionAfter(inst, token, "," );

	this:QueueInjectionBefore(inst, value.token, "_OPS[\"" .. op.signature .. "\"](");

	if (op.context) then
	   this:QueueInjectionBefore(inst, value.token, "CONTEXT,");
	end

	if (inst.__com) then
		this:QueueRemove(inst, inst.__com)
	end

	if (not keepclass) then
		this:QueueRemove(isnt, cls);
	else
		this:QueueReplace(isnt, cls, ", '" .. cls.data .. "'");
	end

	this:QueueRemove(inst, inst.__ass);

	this:QueueReplace(inst, inst.__rsb, "," );

	this:QueueInjectionAfter(inst, expr.final, ")");

	this.__operators[op.signature] = op.operator;

	return op.result, op.rCount;
end

--[[
]]

function COMPILER.Compile_FOR(this, inst, token, expressions)

	local start = expressions[1];
	local tStart = this:Compile(start);
	local _end = expressions[2];
	local tEnd = this:Compile(_end);
	local step = expressions[3];

	if (not step and (inst.class ~= "n" or tStart  ~= "n" or tEnd ~= "n")) then
		this:Throw(token, "No such loop 'for(%s i = %s; %s)'.", name(inst.class), name(tStart), name(tEnd));
	elseif (step) then
		local tStep = this:Compile(step);
		if (inst.class ~= "n" or tStart  ~= "n" or tEnd ~= "n" or tEnd ~= "n" or tStep ~= "n") then
			this:Throw(token, "No such loop 'for(%s i = %s; %s; %s)'.", name(inst.class), name(tStart), name(tEnd), name(tStep));
		end
	end

	this:PushScope();
	this:SetOption("loop", true);
	this:AssignVariable(token, true, inst.variable.data, inst.class, nil);

	this:Compile(inst.stmts);

	this:PopScope();
end

function COMPILER.Compile_WHILE(this, inst, token, expressions)
	this:Compile(inst.condition);

	this:PushScope();
		this:SetOption("loop", true);
		this:Compile(inst.block);
	this:PopScope();
end

function COMPILER.Compile_EACH(this, inst, token, expr)
	local r, c = this:Compile(expr);
	local op = this:GetOperator("itor", r);

	if (not op) then
		this:Throw(token, "%s can not be used inside a foreach loop", name(r));
	end

	this:PushScope();
	this:SetOption("loop", true);

	if inst.kType then
		this:AssignVariable(token, true, inst.kValue, inst.kType,  nil);
	end

	this:AssignVariable(token, true, inst.vValue, inst.vType, nil);

	this:Compile(inst.block);
	this:PopScope();

	this:QueueInjectionBefore(inst, inst.__in, "_kt, _kv, _vt, _vv");

	if (isfunction(op.operator)) then
		this:QueueInjectionBefore(inst, expr.token, "_OPS[\"" .. op.signature .. "\"](");

		if (op.context) then
		   this:QueueInjectionBefore(inst, expr.token, "CONTEXT,");
		end

		this:QueueInjectionAfter(inst, expr.final, ")");

		this.__operators[op.signature] = op.operator;
	end

	injectNewLine = true;

	local pos = inst.block.token;

	if (inst.kType) then
		if (inst.kType ~= "_vr") then
			this:QueueInjectionAfter(inst, pos, string_format("if (_kt ~= %q) then continue end", inst.kType));
			this:QueueInjectionAfter(inst, pos, string_format("local %s = _kv", inst.kValue));
		else
			this:QueueInjectionAfter(inst, pos, string_format("local %s = {_kt, _kv}", inst.kValue));
		end
	end

	if (inst.vType) then
		if (inst.vType ~= "_vr") then
			this:QueueInjectionAfter(inst, pos, string_format("if (_vt ~= %q) then continue end", inst.vType));
			this:QueueInjectionAfter(inst, pos, string_format("local %s = _vv", inst.vValue));
		else
			this:QueueInjectionAfter(inst, pos, string_format("local %s = {_vt, _vv}", inst.vValue));
		end
	end

	injectNewLine = false;
end

--[[

]]

function COMPILER.Compile_TRY(this, inst, token, expressions)
	this:QueueReplace(inst, token, "local");

	this:QueueInjectionAfter(inst, token, "ok", ",", inst.__var.data, "=", "pcall(");

	this:PushScope();
		this:SetOption("canReturn", false);
		this:SetOption("loop", false);

	this:Compile(inst.protected);

	this:PopScope();

	this:QueueInjectionAfter(inst, inst.protected.final, ");", "if", "(", "not", "ok", "and", inst.__var.data, ".", "state", "==", "'runtime'", ")");

	this:QueueRemove(inst, inst.__catch);
	this:QueueRemove(inst, inst.__lpa);
	this:QueueRemove(inst, inst.__var);
	this:QueueRemove(inst, inst.__rpa);

	this:PushScope();
	this:SetOption("loop", false);

	this:AssignVariable(token, true, inst.__var.data, "_er", nil);

	this:Compile(inst.catch);

	this:PopScope();

	this:QueueInjectionAfter(inst, inst.catch.final, "elseif (not ok) then error(", inst.__var.data, ", 0) end");
end

--[[
]]

function COMPILER.Compile_INPORT(this, inst, token)
	if (this:GetOption("state") ~= EXPR_SERVER) then
		this:Throw(token, "Wired input('s) must be defined server side.");
	end

	for _, token in pairs(inst.variables) do
		local var = token.data;

		if (var[1] ~= string_upper(var[1])) then
			this:Throw(token, "Invalid name for wired input %s, name must be cammel cased");
		end

		local class, scope, info = this:AssignVariable(token, true, var, inst.class, 0);

		if (info) then
			info.prefix = "INPUT";
		end

		this.__directives.inport[var] = {class = inst.class, wire = inst.wire_type, func = inst.wire_func};
	end
end

function COMPILER.Compile_OUTPORT(this, inst, token)
	if (this:GetOption("state") ~= EXPR_SERVER) then
		this:Throw(token, "Wired output('s) must be defined server side.");
	end

	for _, token in pairs(inst.variables) do
		local var = token.data;

		if (var[1] ~= string_upper(var[1])) then
			this:Throw(token, "Invalid name for wired output %s, name must be cammel cased");
		end

		local class, scope, info = this:AssignVariable(token, true, var, inst.class, 0);

		if (info) then
			info.prefix = "OUTPUT";
		end

		this.__directives.outport[var] = {class = inst.class, wire = inst.wire_type, func = inst.wire_func, func_in = inst.wire_func2};
	end
end

--[[
	Include support: Huge Work In Progress, I will not like this how ever it comes out.
]]

local function Inclucde_ROOT(this, inst, token, stmts)
	for i = 1, #stmts do
		this:Compile(stmts[i]);
	end

	return "", 0;
end

function COMPILER.Compile_INCLUDE(this, inst, token, file_path)
	local script;

	if (CLIENT) then
		script = file.Read("golem/" .. file_path .. ".txt", "DATA");
	elseif (SERVER) then
		script = this.__files[file_path];
	end

	local Toker = EXPR_TOKENIZER.New();

	Toker:Initialize("EXPADV", script);

	local ok, res = Toker:Run();

	if ok then
		local Parser = EXPR_PARSER.New();

		Parser:Initialize(res);

		Parser.__directives = this.__directives;

		ok, res = Parser:Run();

		if ok then
			local Compiler = EXPR_COMPILER.New();

			Compiler:Initialize(res);

			Compiler.Compile_ROOT = Inclucde_ROOT;
			Compiler.__directives = this.__directives;

			Compiler.__scope = this.__scope;
			Compiler.__scopeID = this.__scopeID ;
			Compiler.__scopeData = this.__scopeData;
			Compiler.__constructors = this.__constructors;
			Compiler.__operators = this.__operators;
			Compiler.__functions = this.__functions;
			Compiler.__methods = this.__methods;
			Compiler.__enviroment = this.__enviroment;

			ok, res = Compiler:Run();

			if (ok) then
				this:QueueInjectionAfter(inst, token, res.compiled);
			end
		end
	end

	if (not ok) then
		if (istable(res)) then
			res.file = file_path;
		end

		error(res, 0);
	end

end

--[[
]]

function COMPILER.StartClass(this, name)
	local classes = this.__scope.classes;

	local newclass = {name = name, constructors = {}, methods = {}, memory = {}, instances = {}};

	classes[name] = newclass;

	return newclass;
end

function COMPILER.GetUserClass(this, name, scope, nonDeep)
	if (not scope) then
		scope = this.__scopeID;
	end

	local v = this.__scopeData[scope].classes[name];

	if (v) then
		return v, v.scope;
	end

	if (not nonDeep) then
		for i = scope, 0, -1 do
			local v = this.__scopeData[i].classes[name];

			if (v) then
				return v, v.scope;
			end
		end
	end
end

function COMPILER.AssToClass(this, token, declaired, varName, class, scope)
	local class, scope, info = this:AssignVariable(token, declaired, varName, class, scope);
	if (declaired) then
		local userclass = this:GetOption("userclass");
		userclass.memory[varName] = info;
		info.atribute = true;
		info.prefix = "vars";
	end

	return class, scope, info;
end



function COMPILER.Compile_CLASS(this, inst, token, stmts)
	local extends;
	local class = this:StartClass(inst.__classname.data);

	class.hash = this:CRC(token, inst.__rcb);

	this.__hashtable[class.hash] = {[class.hash] = true};

	this:PushScope();

		this:SetOption("userclass", class);

		if (inst.__ext) then
			extends = this:GetUserClass(inst.__exttype.data);

			if (not extends) then
				this:Throw(token, "Can not extend user class from none user class %s.", inst.__exttype.data);
			end

			class.extends = extends;

			for name, info in pairs(extends.memory) do
				this:AssToClass(token, true, name, info.class);
			end

			for name, info in pairs(extends.constructors) do
				class.constructors[name] = info;
			end

			for name, info in pairs(extends.methods) do
				class.methods[name] = info;
			end

			this.__hashtable[extends.hash][class.hash] = true;

			this:QueueRemove(inst, inst.__ext);
			this:QueueRemove(inst, inst.__exttype);
		end

		for i = 1, #stmts do
			this:Compile(stmts[i]);
		end

		if (inst.implements) then
			for _, imp in pairs(inst.implements) do
				local interface = this:GetInterface(imp.data);

				if (not interface) then
					this:Throw(imp, "No sutch interface %s", imp.data);
				end

				for name, info in pairs(interface.methods) do
					local overrride = class.methods[name];

					if (not overrride) then
						this:Throw(token, "Missing method %s(%s) on class %s, for interface %s", info.name, inst.params or "", inst.__classname.data, imp.data);
					end

					if (overrride and info.result ~= overrride.result) then
						this:Throw(overrride.token, "Interface method %s(%s) on %s must return %s", info.name, inst.params or "", imp.data, name(info.result));
					end

					if (overrride and info.count ~= overrride.count) then
						this:Throw(overrride.token, "Interface method %s(%s) on %s must return %i values", info.name, inst.params or "", imp.data, info.count);
					end
				end

				this.__hashtable[interface.hash][class.hash] = true;
			end
		end

		if (not extends and not class.valid) then
			this:Throw(token, "Class %s requires at least one constructor.", class.name);
		end

	this:PopScope();

	this:QueueReplace(inst, token, "local");
	this:QueueRemove(inst, inst.__lcb);
	this:QueueInjectionAfter(inst, inst.__lcb, " = { vars = { }, hash = '" .. class.hash .. "'};", class.name, ".__index =", class.name); -- extends and extends.name or class.name);
	if (extends) then this:QueueInjectionAfter(inst, inst.__lcb, "setmetatable(", class.name, ",", extends.name, ");") end
	this:QueueRemove(inst, inst.__rcb);

	injectNewLine = true;
	this:QueueInjectionAfter(inst, inst.__lcb, class.name, ".vars.__index =", class.name, ".vars"); -- extends and extends.name or class.name, ".vars");
	if (extends) then this:QueueInjectionAfter(inst, inst.__lcb, "setmetatable(", class.name, ".vars,", extends.name, " .vars);") end
	injectNewLine = false;

	return "", 0;
end

--[[Notes.
function downCast()
	if from-class is extended from to-class then return to-class
end

function upCast()
	if to-class is extended from from-class then

end
]]


function COMPILER.Compile_FEILD(this, inst, token, expressions)
	local expr = expressions[1];
	local type = this:Compile(expr);
	local userclass = this:GetUserClass(type);

	if (not userclass) then
		-- this:Throw(token, "Unable to reference feild %s.%s here", name(type), inst.__feild.data);

		local cls = E3Class(type);
		local info = cls.atributes[inst.__feild.data];

		if (not info) then
			this:Throw(token, "No sutch atribute %s.%s", name(type), inst.__feild.data);
		end

		return info.class, 1;
	end

	local info = userclass.memory[inst.__feild.data];

	if (not info) then
		this:Throw(token, "No sutch atribute %s.%s", type, inst.__feild.data);
	end

	if (info) then
		this:QueueReplace(inst, inst.__feild, info.prefix .. "." .. inst.__feild.data);
	end

	return info.class, 1;
end

function COMPILER.Compile_DEF_FEILD(this, inst, token, expressions)
	local tArgs = #expressions;
	local userclass = this:GetOption("userclass");

	local tArgs = #expressions;

	local results = {};

	for i = 1, tArgs do
		local arg = expressions[i];
		local r, c = this:Compile(arg);

		if (not inst.variables[i]) then
			this:Throw(arg.token, "Unable to assign here, value #%i has no matching variable.", i);
		elseif (i < tArgs) then
			results[#results + 1] = {r, arg, true};
		else
			for j = 1, c do
				results[#results + 1] = {r, arg, j == 1};
			end
		end
	end

	for i = 1, #inst.variables do
		local result = results[i];
		local token = inst.variables[i];
		local var = token.data;

		local class, scope, info = this:AssToClass(token, true, var, inst.class);

		if (not result) then
			this:QueueRemove(inst, token);
			--this:Throw(token, "Unable to assign variable %s, no matching value.", var);
		else
			if (info) then
				this:QueueReplace(inst, token, userclass.name .. ".vars." .. var);
			end

			this.__defined[var] = true;

			if (result[1] ~= inst.class) then
				local casted = false;
				local arg = result[2];

				if (result[3]) then
					-- TODO: CAST
				end

				if (not casted) then
					this:AssToClass(arg.token, true, var, result[1]);
				end
			end
		end
	end

	if #results == 0 then
		local token = this:OffsetToken(inst.final, 1);

		if(token and token.type == "sep") then
			this:QueueRemove(inst, token);
		end
	end

	this.__defined = {};

	return "", 0;
end

function COMPILER.Compile_SET_FEILD(this, inst, token, expressions)

	local info;
	local atribute = inst.__feild.data;
	local r1, c1 = this:Compile(expressions[1]);
	local r2, c2 = this:Compile(expressions[2]);
	local cls = E3Class(r1);

	if (not cls) then
		local userclass = this:GetClassOrInterface(r1);
		info = userclass.memory[atribute];
	else
		info = cls.atributes[atribute];
	end

	if (not info) then
		this:Throw(token, "No sutch atribute %s.%s", name(r1), atribute);
	end

	if (info.class ~= r2) then
		this:Throw( token, "Can not assign atribute %s.%s of type %s with %s", name(r1), atribute, name(info.class), name(r2));
	end

	if (not cls) then
		this:QueueReplace(inst, inst.__feild, "vars." .. atribute);
	elseif (info.feild) then
		this:QueueReplace(inst, inst.__feild, info.feild);
	end

	return info.class, 1;
end

--[[
]]

function COMPILER.Compile_CONSTCLASS(this, inst, token, expressions)
	this:PushScope();
	this:SetOption("loop", false);

	local userclass = this:GetOption("userclass");

	this:AssignVariable(token, true, "this", userclass.name);

	for _, param in pairs(inst.params) do
		local var = param[2];
		local class = param[1];

		this:AssignVariable(token, true, var, class);
	end

	local signature = string_format("constructor(%s)", inst.signature);

	userclass.valid = true;
	userclass.constructors[signature] = signature;

	this:Compile(inst.stmts);

	this:PopScope();

	this:QueueInjectionAfter(inst, inst.__name, "['" .. signature .. "']", "=", "function")

	injectNewLine = true;
	local class_line = string_format("local this = setmetatable({vars = setmetatable({}, %s.vars)}, %s)", userclass.name, userclass.name);
	this:QueueInjectionAfter(inst, inst.__postBlock, class_line);
	this:QueueInjectionBefore(inst, inst.final, "return this;");
	injectNewLine = false;
end

function COMPILER.Compile_DEF_METHOD(this, inst, token, expressions)
	this:PushScope();

	local userclass = this:GetOption("userclass");

	this:AssignVariable(token, true, "this", userclass.name);

	for _, param in pairs(inst.params) do
		local var = param[2];
		local class = param[1];

		this:AssignVariable(token, true, var, class);
	end

	local signature = string_format("@%s(%s)", inst.__name.data, inst.signature);

	local overrride = userclass.methods[signature];

	local meth = {};
	meth.sig = signature;
	meth.name = inst.__name.data;
	meth.result = inst.__typ.data;
	meth.token = token;
	userclass.methods[signature] = meth;

	this:SetOption("udf", (this:GetOption("udf") or 0) + 1);
	this:SetOption("loop", false);
	this:SetOption("canReturn", true);
	this:SetOption("retunClass", meth.result);
	this:SetOption("retunCount", meth.result ~= "" and -1 or 0);

	this:Compile(inst.stmts);

	local count = this:GetOption("retunCount");

	this:PopScope();

	if (count == -1) then
		count = 0;
	end

	meth.count = count;

	if (overrride and meth.result ~= overrride.result) then
		this:Throw(token, "Overriding method %s(%s) must return %s", inst.__name.data, inst.signature, name(overrride.result));
	end

	if (overrride and meth.count ~= overrride.count) then
		this:Throw(token, "Overriding method %s(%s) must return %i values", inst.__name.data, inst.signature, overrride.count);
	end

	this:QueueReplace(inst, token, userclass.name);
	this:QueueRemove(inst, inst.__name)
	this:QueueRemove(inst, inst.__typ)
	this:QueueRemove(inst, inst.__lpa)
	this:QueueInjectionAfter(inst, inst.__name, "['" .. signature .. "']", "=", "function(this")

	injectNewLine = true;
	local error = string_format("Attempt to call user method '%s.%s(%s)' using alien class of the same name.", userclass.name, inst.__name.data, inst.signature);
	this:QueueInjectionAfter(inst, inst.__preBlock, string_format("if(not CheckHash(%q, this)) then CONTEXT:Throw(%q); end", userclass.hash, error))
	injectNewLine = false;

	if (#inst.params >= 1) then
		this:QueueInjectionAfter(inst, inst.__name, ",")
	end
end

function COMPILER.Compile_TOSTR(this, inst, token, expressions)
	local userclass = this:GetOption("userclass");

	this:PushScope();
	this:SetOption("loop", false);

	this:AssignVariable(token, true, "this", userclass.name);

	this:SetOption("udf", (this:GetOption("udf") or 0) + 1);
	this:SetOption("canReturn", true);
	this:SetOption("retunClass", "s");
	this:SetOption("retunCount", 1);

	this:Compile(inst.stmts);

	this:PopScope();

	this:QueueInjectionBefore(inst, inst.__var, userclass.name, ".")
	this:QueueReplace(inst, inst.__var, "__tostring");
	this:QueueInjectionAfter(inst, inst.__var, "=", "function")
	this:QueueInjectionAfter(inst, this:OffsetToken(inst.__var, 1), "this")

	injectNewLine = true;
	local error = string_format("Attempt to call user operation '%s.tostring()' using alien class of the same name.", userclass.name);
	this:QueueInjectionAfter(inst, inst.__preBlock, string_format("if(not CheckHash(%q, this)) then CONTEXT:Throw(%q); end", userclass.hash, error))
	injectNewLine = false;
end

--[[
]]

function COMPILER.StartInterface(this, name)
	local interfaces = this.__scope.interfaces;

	local newinterfaces = {name = name, methods = {}};

	interfaces[name] = newinterfaces;

	return newinterfaces;
end

function COMPILER.GetInterface(this, name, scope, nonDeep)
	if (not scope) then
		scope = this.__scopeID;
	end

	local v = this.__scopeData[scope].interfaces[name];

	if (v) then
		return v, v.scope;
	end

	if (not nonDeep) then
		for i = scope, 0, -1 do
			local v = this.__scopeData[i].interfaces[name];

			if (v) then
				return v, v.scope;
			end
		end
	end
end

function COMPILER.Compile_INTERFACE(this, inst, token, stmts)
	local extends;
	local interface = this:StartInterface(inst.interface);

	interface.hash = this:CRC(token, inst.__rcb);

	this.__hashtable[interface.hash] = {[interface.hash] = true};

	this:PushScope();

		this:SetOption("interface", interface);

		for i = 1, #stmts do
			this:Compile(stmts[i]);
		end

	this:PopScope();

	return "", 0;
end

function COMPILER.Compile_INTERFACE_METHOD(this, inst, token)
	local interface = this:GetOption("interface");

	local meth = {};
	meth.name = inst.name;
	meth.result = inst.result;
	meth.params = table_concat(inst.parameters, ",");
	meth.sig = string_format("@%s(%s)", inst.name, meth.params);
	meth.token = token;

	if (inst.count == -1) then
		inst.count = 0;
	end

	meth.count = inst.count;

	interface.methods[meth.sig] = meth;
end

function COMPILER.GetClassOrInterface(this, name, scope, nonDeep)
	if (not scope) then
		scope = this.__scopeID;
	end

	local v = this.__scopeData[scope].classes[name] or this.__scopeData[scope].interfaces[name];

	if (v) then
		return v, v.scope;
	end

	if (not nonDeep) then
		for i = scope, 0, -1 do
			local v = this.__scopeData[i].classes[name] or this.__scopeData[i].interfaces[name];

			if (v) then
				return v, v.scope;
			end
		end
	end
end

EXPR_COMPILER = COMPILER;
