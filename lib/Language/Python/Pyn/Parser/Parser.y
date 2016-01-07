{
-----------------------------------------------------------------------------
-- |
-- Module      : Language.Python.Pyn.Parser.Parser 
-- Copyright   : (c) 2016 Savor d'Isavano
-- License     : MIT
-- Maintainer  : anohigisavay@gmail.com
-- Stability   : experimental
-- Portability : ghc
--
-- Pyn parser
-----------------------------------------------------------------------------

module Language.Python.Pyn.Parser.Parser (parseFileInput, parseSingleInput, parseEval) where

import Language.Python.Pyn.Parser.Lexer
import Language.Python.Common.Token as Token 
import Language.Python.Common.AST as AST
import Language.Python.Common.ParserMonad
import Language.Python.Common.SrcLocation
import Language.Python.Common.ParserUtils
import Data.Either (rights, either)
import Data.Maybe (maybeToList)
}

%name parseFileInput file_input 
%name parseSingleInput single_input 
%name parseEval eval_input

%tokentype { Token } 
%error { parseError } 
%monad { P } { thenP } { returnP }
%lexer { lexCont } { EOFToken {} }

%token 
   '='             { AssignToken {} }
   '('             { LeftRoundBracketToken {} }
   ')'             { RightRoundBracketToken {} }
   '['             { LeftSquareBracketToken {} }
   ']'             { RightSquareBracketToken {} }
   '{'             { LeftBraceToken {} }
   '}'             { RightBraceToken {} }
   ','             { CommaToken {} }
   ';'             { SemiColonToken {} }
   ':'             { ColonToken {} }
   '+'             { PlusToken {} }
   '-'             { MinusToken {} }
   '*'             { MultToken {} }
   '**'            { ExponentToken {} }
   '/'             { DivToken {} }
   '//'            { FloorDivToken {} }
   '>'             { GreaterThanToken {} }
   '<'             { LessThanToken {} }
   '=='            { EqualityToken {} }
   '>='            { GreaterThanEqualsToken {} }
   '<='            { LessThanEqualsToken {} }
   '|'             { BinaryOrToken {} }
   '^'             { XorToken {} }      
   '&'             { BinaryAndToken {} }      
   '>>'            { ShiftRightToken {} }
   '<<'            { ShiftLeftToken {} }
   '%'             { ModuloToken {} }
   '~'             { TildeToken {} }
   '!='            { NotEqualsToken {} }
   '<>'            { NotEqualsV2Token {} }
   '.'             { DotToken {} }
   '`'             { BackQuoteToken {} }
   '+='            { PlusAssignToken {} }
   '-='            { MinusAssignToken {} }
   '*='            { MultAssignToken {} }
   '/='            { DivAssignToken {} }
   '%='            { ModAssignToken {} }
   '**='           { PowAssignToken {} }
   '&='            { BinAndAssignToken {} }
   '|='            { BinOrAssignToken {} }
   '^='            { BinXorAssignToken {} }
   '<<='           { LeftShiftAssignToken {} }
   '>>='           { RightShiftAssignToken {} }
   '//='           { FloorDivAssignToken {} } 
   '@'             { AtToken {} }
   '->'            { RightArrowToken {} }
   'and'           { AndToken {} }
   'as'            { AsToken {} }
   'assert'        { AssertToken {} }
   'break'         { BreakToken {} }
   'bytestring'    { ByteStringToken {} }
   'class'         { ClassToken {} }
   'continue'      { ContinueToken {} }
   'dedent'        { DedentToken {} }
   'def'           { DefToken {} }
   'del'           { DeleteToken {} }
   'elif'          { ElifToken {} }
   'else'          { ElseToken {} }
   'except'        { ExceptToken {} }
   'exec'          { ExecToken {} }
   'finally'       { FinallyToken {} }
   'float'         { FloatToken {} }
   'for'           { ForToken {} }
   'from'          { FromToken {} }
   'global'        { GlobalToken {} }
   'ident'         { IdentifierToken {} }
   'if'            { IfToken {} }
   'imaginary'     { ImaginaryToken {} }
   'import'        { ImportToken {} }
   'indent'        { IndentToken {} }
   'in'            { InToken {} }
   'integer'       { IntegerToken {} }
   'long_integer'  { LongIntegerToken {} }
   'is'            { IsToken {} }
   'lambda'        { LambdaToken {} }
   'NEWLINE'       { NewlineToken {} }
   'not'           { NotToken {} }
   'or'            { OrToken {} }
   'pass'          { PassToken {} }
   'print'         { PrintToken {} }
   'raise'         { RaiseToken {} }
   'return'        { ReturnToken {} }
   'string'        { StringToken {} }
   'try'           { TryToken {} }
   'unicodestring' { UnicodeStringToken {} }
   'while'         { WhileToken {} }
   'with'          { WithToken {} }
   'yield'         { YieldToken {} }

%%

pair(p,q): p q { ($1, $2) }

left(p,q): p q { $1 }
right(p,q): p q { $2 }

or(p,q)
   : p  { $1 }
   | q  { $1 }

either(p,q)
   : p { Left $1 }
   | q { Right $1 }

opt(p)
   :    { Nothing }
   | p  { Just $1 }

rev_list1(p)
   : p               { [$1] }
   | rev_list1(p) p  { $2 : $1 }

many1(p)
   : rev_list1(p) { reverse $1 }

many0(p)
   : many1(p) { $1 }
   |         { [] }

sepOptEndBy(p,sep) 
   : sepByRev(p,sep) ',' { reverse $1 }
   | sepByRev(p,sep) { reverse $1 }

sepBy(p,sep): sepByRev(p,sep) { reverse $1 }

sepByRev(p,sep)
   : p { [$1] }
   | sepByRev(p,sep) sep p { $3 : $1 }

NAME :: { IdentSpan }
NAME : 'ident' { Ident (token_literal $1) (getSpan $1) }

{- 
   Note: newline tokens in the grammar:
   It seems there are some dubious uses of NEWLINE in the grammar. 
   This is corroborated by this posting:
   http://mail.python.org/pipermail/python-dev/2005-October/057014.html
   The general idea is that the lexer does not generate NEWLINE tokens for
   lines which contain only spaces or comments. However, the grammar sometimes
   suggests that such tokens may exist. 
-}

-- single_input: NEWLINE | simple_stmt | compound_stmt NEWLINE 

{- 
   We don't support the newline at the end of a compound stmt 
   because the lexer would not produce a newline there. It seems like a weirdness
   in the way the interactive input works. 
-}

single_input :: { [StatementSpan] }
single_input
   : 'NEWLINE' { [] }
   | simple_stmt { $1 } 
   | compound_stmt {- No newline here! -} { [$1] } 

-- file_input: (NEWLINE | stmt)* ENDMARKER

file_input :: { ModuleSpan }
file_input 
   : many0(either('NEWLINE',stmt)) {- No need to mention ENDMARKER -} 
     { Module (concat (rights $1)) }

-- eval_input: testlist NEWLINE* ENDMARKER

eval_input :: { ExprSpan }
eval_input : testlist many0('NEWLINE') {- No need to mention ENDMARKER -} { $1 }

--  decorator: '@' dotted_name [ '(' [arglist] ')' ] NEWLINE

opt_paren_arg_list :: { [ArgumentSpan] }
opt_paren_arg_list: opt(paren_arg_list) { concat (maybeToList $1) }

paren_arg_list :: { [ArgumentSpan] }
paren_arg_list : '(' optional_arg_list ')' { $2 }

decorator :: { DecoratorSpan }
decorator 
   : '@' dotted_name opt_paren_arg_list 'NEWLINE' 
     { makeDecorator $1 $2 $3 }

-- decorators: decorator+

decorators :: { [DecoratorSpan] }
decorators : many1(decorator) { $1 }

-- decorated: decorators (classdef | funcdef)

decorated :: { StatementSpan }
decorated 
   : decorators or(classdef,funcdef) 
     { makeDecorated $1 $2 } 

-- funcdef: 'def' NAME parameters ':' suite

funcdef :: { StatementSpan }
funcdef 
   : 'def' NAME parameters opt(right('->',test)) ':' suite
     { makeFun $1 $2 $3 $4 $6 }

-- parameters: '(' [varargslist] ')'

parameters :: { [ParameterSpan] }
parameters : '(' opt(varargslist) ')' { concat (maybeToList $2) }

{-
   varargslist: ((fpdef ['=' test] ',')* ('*' NAME [',' '**' NAME] | '**' NAME) | fpdef ['=' test] (',' fpdef ['=' test])* [','])
-}

{- 
   There is some tedious similarity in these rules to the ones for
   TypedArgsList. varargslist is used for lambda functions, and they
   do not have parentheses around them (unlike function definitions).
   Therefore lambda parameters cannot have the optional annotations
   that normal functions can, because the annotations are introduced
   using a colon. This would cause ambibguity with the colon
   that marks the end of the lambda parameter list!
-}

varargslist :: { [ParameterSpan] }
varargslist : sepOptEndBy(one_varargs_param,',') {% checkParameters $1 }

one_varargs_param :: { ParameterSpan }
one_varargs_param
   : '*' NAME { makeStarParam $1 (Just ($2, Nothing)) }
   | '**' NAME { makeStarStarParam $1 ($2, Nothing) } 
   | fpdef optional_default { makeTupleParam $1 $2 }

optional_default :: { Maybe ExprSpan }
optional_default: opt(equals_test) { $1 }

equals_test :: { ExprSpan }
equals_test: '=' test { $2 }

-- fpdef: NAME | '(' fplist ')'

fpdef :: { ParamTupleSpan }
fpdef
   : NAME opt(colon_test) { ParamTupleAnnotatedName $1 $2 (getSpan $1) }
   | '(' fplist ')' { ParamTuple $2 (spanning $1 $3) }

colon_test :: { ExprSpan }
colon_test: ':' test { $2 }

-- fplist: fpdef (',' fpdef)* [',']

fplist :: { [ParamTupleSpan] }
fplist: sepOptEndBy(fpdef,',') { $1 }

-- stmt: simple_stmt | compound_stmt 

stmt :: { [StatementSpan] }
stmt 
   : simple_stmt { $1 }
   | compound_stmt { [$1] }

-- simple_stmt: small_stmt (';' small_stmt)* [';'] NEWLINE 

simple_stmt :: { [StatementSpan] }
simple_stmt : small_stmts opt(';') 'NEWLINE' { reverse $1 }

small_stmts :: { [StatementSpan] }
small_stmts 
   : small_stmt                 { [$1] }
   | small_stmts ';' small_stmt { $3 : $1 }

{-
small_stmt: (expr_stmt | print_stmt  | del_stmt | pass_stmt | flow_stmt |
             import_stmt | global_stmt | exec_stmt | assert_stmt)

-}

small_stmt :: { StatementSpan }
small_stmt 
   : expr_stmt     { $1 }
   | print_stmt    { $1 }
   | del_stmt      { $1 }
   | pass_stmt     { $1 }
   | flow_stmt     { $1 }
   | import_stmt   { $1 }
   | global_stmt   { $1 }
   | exec_stmt     { $1 }
   | assert_stmt   { $1 }

-- expr_stmt: testlist (augassign (yield_expr|testlist) | ('=' (yield_expr|testlist))*)

expr_stmt :: { StatementSpan }
expr_stmt 
   : testlist either(many_assign, augassign_yield_or_test_list) 
   { makeAssignmentOrExpr $1 $2 }

many_assign :: { [ExprSpan] }
many_assign : many0(right('=', yield_or_test_list)) { $1 }

yield_or_test_list :: { ExprSpan }
yield_or_test_list : or(yield_expr,testlist) { $1 }

augassign_yield_or_test_list :: { (AssignOpSpan, ExprSpan) }
augassign_yield_or_test_list : augassign yield_or_test_list { ($1, $2) }

{- 
   augassign: ('+=' | '-=' | '*=' | '/=' | '%=' | '&=' | '|=' | '^=' |
            '<<=' | '>>=' | '**=' | '//=') 
-}

augassign :: { AssignOpSpan }
augassign
   : '+='  { AST.PlusAssign (getSpan $1) }
   | '-='  { AST.MinusAssign (getSpan $1) } 
   | '*='  { AST.MultAssign (getSpan $1) }
   | '/='  { AST.DivAssign (getSpan $1) }
   | '%='  { AST.ModAssign (getSpan $1) } 
   | '**=' { AST.PowAssign (getSpan $1) }
   | '&='  { AST.BinAndAssign (getSpan $1) } 
   | '|='  { AST.BinOrAssign (getSpan $1) }
   | '^='  { AST.BinXorAssign (getSpan $1) }
   | '<<=' { AST.LeftShiftAssign (getSpan $1) }
   | '>>=' { AST.RightShiftAssign (getSpan $1) }
   | '//=' { AST.FloorDivAssign (getSpan $1) } 

{- 
   print_stmt: 'print' ( [ test (',' test)* [','] ] |
                      '>>' test [ (',' test)+ [','] ] )
-}

print_stmt :: { StatementSpan }
print_stmt
   : 'print' '>>' print_exprs {  makePrint True (Just $3) (spanning $1 $3) }
   | 'print' opt(print_exprs) { makePrint False $2 (spanning $1 $2) } 

print_exprs :: { ([ExprSpan], Maybe Token) }
print_exprs : testlistrev opt_comma { (reverse $1, $2) }

-- del_stmt: 'del' exprlist

del_stmt :: { StatementSpan }
del_stmt : 'del' exprlist { AST.Delete $2 (spanning $1 $2) }

-- pass_stmt: 'pass'

pass_stmt :: { StatementSpan }
pass_stmt : 'pass' { AST.Pass (getSpan $1) } 

-- flow_stmt: break_stmt | continue_stmt | return_stmt | raise_stmt | yield_stmt

flow_stmt :: { StatementSpan }
flow_stmt 
   : break_stmt    { $1 }
   | continue_stmt { $1 }
   | return_stmt   { $1 }
   | raise_stmt    { $1 }
   | yield_stmt    { $1 }

-- break_stmt: 'break'

break_stmt :: { StatementSpan }
break_stmt : 'break' { AST.Break (getSpan $1) }

-- continue_stmt: 'continue'

continue_stmt :: { StatementSpan }
continue_stmt : 'continue' { AST.Continue (getSpan $1) }

-- return_stmt: 'return' [testlist]

return_stmt :: { StatementSpan }
return_stmt : 'return' optional_testlist { makeReturn $1 $2 }

-- yield_stmt: yield_expr

yield_stmt :: { StatementSpan }
yield_stmt : yield_expr { StmtExpr $1 (getSpan $1) } 

-- raise_stmt: 'raise' [test ['from' test]]
-- raise_stmt: 'raise' [test [',' test [',' test]]]

raise_stmt :: { StatementSpan }
raise_stmt : 'raise' opt(pair(test, opt(pair(right(',',test), opt(right(',', test)))))) 
             { AST.Raise (RaiseV2 $2) (spanning $1 $2) }

-- import_stmt: import_name | import_from

import_stmt :: { StatementSpan }
import_stmt: or(import_name, import_from) { $1 }

-- import_name: 'import' dotted_as_names

import_name :: { StatementSpan }
import_name : 'import' dotted_as_names { AST.Import $2 (spanning $1 $2) }

{-
   import_from: ('from' ('.'* dotted_name | '.'+)
              'import' ('*' | '(' import_as_names ')' | import_as_names))
-}

import_from :: { StatementSpan }
import_from : 'from' import_module 'import' star_or_as_names 
              { FromImport $2 $4 (spanning $1 $4) }

import_module :: { ImportRelativeSpan }
import_module: import_module_dots { makeRelative $1 }

import_module_dots :: { [Either Token DottedNameSpan] }
import_module_dots
   : '.'                      { [ Left $1 ] } 
   | dotted_name              { [ Right $1 ] } 
   | '.' import_module_dots   { Left $1 : $2 } 

star_or_as_names :: { FromItemsSpan }
star_or_as_names
   : '*'                     { ImportEverything (getSpan $1) }
   | '(' import_as_names ')' { $2 }
   | import_as_names         { $1 } 

-- import_as_name: NAME ['as' NAME]
import_as_name :: { FromItemSpan }
import_as_name 
   : NAME optional_as_name { FromItem $1 $2 (spanning $1 $2) }

-- dotted_as_name: dotted_name ['as' NAME]

dotted_as_name :: { ImportItemSpan }
dotted_as_name 
   : dotted_name optional_as_name  
     { ImportItem $1 $2 (spanning $1 $2) }

-- import_as_names: import_as_name (',' import_as_name)* [',']

import_as_names :: { FromItemsSpan }
import_as_names : sepOptEndBy(import_as_name, ',') { FromItems $1 (getSpan $1) }

-- dotted_as_names: dotted_as_name (',' dotted_as_name)*

dotted_as_names :: { [ImportItemSpan] }
dotted_as_names : sepBy(dotted_as_name,',') { $1 }

-- dotted_name: NAME ('.' NAME)* 

dotted_name :: { DottedNameSpan }
dotted_name : NAME many0(right('.', NAME)) { $1 : $2 }

-- global_stmt: 'global' NAME (',' NAME)*

global_stmt :: { StatementSpan }
global_stmt : 'global' one_or_more_names { AST.Global $2 (spanning $1 $2) }

one_or_more_names :: { [IdentSpan] }
one_or_more_names: sepBy(NAME, ',') { $1 }

-- exec_stmt: 'exec' expr ['in' test [',' test]]
exec_stmt :: { StatementSpan }
exec_stmt
   : 'exec' expr opt(right('in', pair(test, opt(right(',', test)))))
     { AST.Exec $2 $3 (spanning (spanning $1 $2) $3) }

-- assert_stmt: 'assert' test [',' test]

assert_stmt :: { StatementSpan }
assert_stmt : 'assert' sepBy(test,',') 
              { AST.Assert $2 (spanning $1 $2) }

-- compound_stmt: if_stmt | while_stmt | for_stmt | try_stmt | with_stmt | funcdef | classdef | decorated 

compound_stmt :: { StatementSpan }
compound_stmt 
   : if_stmt    { $1 } 
   | while_stmt { $1 }
   | for_stmt   { $1 }
   | try_stmt   { $1 }
   | with_stmt  { $1 }
   | funcdef    { $1 } 
   | classdef   { $1 }
   | decorated  { $1 }

-- if_stmt: 'if' test ':' suite ('elif' test ':' suite)* ['else' ':' suite]

if_stmt :: { StatementSpan }
if_stmt : 'if' test ':' suite many0(elif) optional_else 
          { Conditional (($2, $4):$5) $6 (spanning (spanning (spanning $1 $4) $5) $6) }

elif :: { (ExprSpan, [StatementSpan]) }
elif : 'elif' test ':' suite { ($2, $4) }

optional_else :: { [StatementSpan] }
optional_else 
   : {- empty -} { [] }
   | 'else' ':' suite { $3 }

-- while_stmt: 'while' test ':' suite ['else' ':' suite] 

while_stmt :: { StatementSpan }
while_stmt 
   : 'while' test ':' suite optional_else 
     { AST.While $2 $4 $5 (spanning (spanning $1 $4) $5) }

-- for_stmt: 'for' exprlist 'in' testlist ':' suite ['else' ':' suite] 

for_stmt :: { StatementSpan }
for_stmt 
   : 'for' exprlist 'in' testlist ':' suite optional_else 
     { AST.For $2 $4 $6 $7 (spanning (spanning $1 $6) $7) }

{- 
   try_stmt: ('try' ':' suite 
               ((except_clause ':' suite)+ ['else' ':' suite] ['finally' ':' suite] | 'finally' ':' suite))
-}

try_stmt :: { StatementSpan }
try_stmt : 'try' ':' suite handlers { makeTry $1 $3 $4 }

handlers :: { ([HandlerSpan], [StatementSpan], [StatementSpan]) }
handlers 
   : one_or_more_except_clauses optional_else optional_finally { ($1, $2, $3) }
   | 'finally' ':' suite { ([], [], $3) }

optional_finally :: { [StatementSpan] }
optional_finally 
   : {- empty -} { [] }
   | 'finally' ':' suite { $3 }

one_or_more_except_clauses :: { [HandlerSpan] }
one_or_more_except_clauses : many1(handler) { $1 }

handler :: { HandlerSpan }
handler : except_clause ':' suite { Handler $1 $3 (spanning $1 $3) }

-- with_stmt: 'with' with_item (',' with_item)*  ':' suite

with_stmt :: { StatementSpan }
with_stmt : 'with' sepOptEndBy(with_item, ',') ':' suite 
           { AST.With  $2 $4 (spanning $1 $4) }

-- with_item: test ['as' expr]

with_item :: { (ExprSpan, Maybe ExprSpan) }
with_item: pair(test,opt(right('as',expr))) { $1 }

-- except_clause: 'except' [test [('as' | ',') test]]

except_clause :: { ExceptClauseSpan }
except_clause : 'except' opt(pair(test, opt(right(or('as',','), test)))) 
                { ExceptClause $2 (spanning $1 $2) }

optional_as_name :: { Maybe IdentSpan }
optional_as_name: opt(right('as', NAME)) { $1 }

-- suite: simple_stmt | NEWLINE INDENT stmt+ DEDENT 
-- Note: we don't have a newline before indent b/c it is redundant

suite :: { [StatementSpan] }
suite 
   : simple_stmt { $1 }
   | {- no newline here! -} 'indent' many1(stmt) 'dedent' { concat $2 } 

-- testlist_safe: old_test [(',' old_test)+ [',']]

testlist_safe :: { ExprSpan }
testlist : old_testlistrev opt_comma { makeTupleOrExpr (reverse $1) $2 }

old_testlistrev :: { [ExprSpan] }
old_testlistrev 
   : old_test { [$1] }
   | old_testlistrev ',' old_test { $3 : $1 }

-- old_test: or_test | old_lambdef

old_test :: { ExprSpan }
old_test: or(or_test,old_lambdef) { $1 }

-- old_lambdef: 'lambda' [varargslist] ':' old_test 

old_lambdef :: { ExprSpan }
old_lambdef: 'lambda' opt_varargslist ':' old_test
             { AST.Lambda $2 $4 (spanning $1 $4) }

-- test: or_test ['if' or_test 'else' test] | lambdef

test :: { ExprSpan }
test 
   : or_test opt(test_if_cond) { makeConditionalExpr $1 $2 } 
   | lambdef { $1 }

test_if_cond :: { (ExprSpan, ExprSpan) }
test_if_cond: 'if' or_test 'else' test { ($2, $4) }

-- lambdef: 'lambda' [varargslist] ':' test

lambdef :: { ExprSpan }
lambdef : 'lambda' opt_varargslist ':' test { AST.Lambda $2 $4 (spanning $1 $4) }

opt_varargslist :: { [ParameterSpan] }
opt_varargslist: opt(varargslist) { concat (maybeToList $1) }

-- or_test: and_test ('or' and_test)* 

or_test :: { ExprSpan }
or_test : and_test many0(pair(or_op,and_test)) { makeBinOp $1 $2 }

or_op :: { OpSpan }
or_op: 'or' { AST.Or (getSpan $1) }

-- and_test: not_test ('and' not_test)* 

and_test :: { ExprSpan }
and_test : not_test many0(pair(and_op, not_test)) { makeBinOp $1 $2 }

and_op :: { OpSpan }
and_op: 'and' { AST.And (getSpan $1) }

-- not_test: 'not' not_test | comparison 

not_test :: { ExprSpan }
not_test
   : 'not' not_test { UnaryOp (AST.Not (getSpan $1)) $2 (spanning $1 $2) }
   | comparison { $1 }

-- comparison: expr (comp_op expr)*

comparison :: { ExprSpan }
comparison : expr many0(pair(comp_op, expr)) { makeBinOp $1 $2 }

-- comp_op: '<'|'>'|'=='|'>='|'<='|'<>'|'!='|'in'|'not' 'in'|'is'|'is' 'not'

comp_op :: { OpSpan }
comp_op
   : '<'        { AST.LessThan (getSpan $1) }
   | '>'        { AST.GreaterThan (getSpan $1) }
   | '=='       { AST.Equality (getSpan $1) }
   | '>='       { AST.GreaterThanEquals (getSpan $1) }
   | '<='       { AST.LessThanEquals (getSpan $1) }
   | '!='       { AST.NotEquals (getSpan $1) }
   | '<>'       { AST.NotEqualsV2 (getSpan $1) }
   | 'in'       { AST.In (getSpan $1) }
   | 'not' 'in' { AST.NotIn (spanning $1 $2) }
   | 'is'       { AST.Is (getSpan $1) }
   | 'is' 'not' { AST.IsNot (spanning $1 $2) }

-- expr: xor_expr ('|' xor_expr)* 

expr :: { ExprSpan }
expr : xor_expr many0(pair(bar_op, xor_expr)) { makeBinOp $1 $2 }

bar_op :: { OpSpan }
bar_op: '|' { AST.BinaryOr (getSpan $1) }

-- xor_expr: and_expr ('^' and_expr)* 

xor_expr :: { ExprSpan }
xor_expr : and_expr many0(pair(hat_op, and_expr)) { makeBinOp $1 $2 }

hat_op :: { OpSpan }
hat_op: '^' { AST.Xor (getSpan $1) }

-- and_expr: shift_expr ('&' shift_expr)* 

and_expr :: { ExprSpan }
and_expr : shift_expr many0(pair(ampersand, shift_expr)) { makeBinOp $1 $2 }

ampersand :: { OpSpan }
ampersand: '&' { AST.BinaryAnd (getSpan $1) }

-- shift_expr: arith_expr (('<<'|'>>') arith_expr)* 

shift_expr :: { ExprSpan }
shift_expr: arith_expr many0(pair(shift_op, arith_expr)) { makeBinOp $1 $2 }

shift_op :: { OpSpan }
shift_op 
   : '<<' { AST.ShiftLeft (getSpan $1) }
   | '>>' { AST.ShiftRight (getSpan $1) }

-- arith_expr: term (('+'|'-') term)*

arith_expr :: { ExprSpan }
arith_expr: term many0(pair(arith_op, term)) { makeBinOp $1 $2 }

arith_op :: { OpSpan }
arith_op
   : '+' { AST.Plus (getSpan $1) }
   | '-' { AST.Minus (getSpan $1) }

-- term: factor (('*'|'/'|'%'|'//') factor)* 

term :: { ExprSpan }
term : factor many0(pair(mult_div_mod_op, factor)) { makeBinOp $1 $2 }

mult_div_mod_op :: { OpSpan }
mult_div_mod_op
   : '*'  { AST.Multiply (getSpan $1) } 
   | '/'  { AST.Divide (getSpan $1) }
   | '%'  { AST.Modulo (getSpan $1) }
   | '//' { AST.FloorDivide (getSpan $1) }

-- factor: ('+'|'-'|'~') factor | power 

factor :: { ExprSpan }
factor 
   : or(arith_op, tilde_op) factor { UnaryOp $1 $2 (spanning $1 $2) } 
   | power { $1 }

tilde_op :: { OpSpan }
tilde_op: '~' { AST.Invert (getSpan $1) }

-- power: atom trailer* ['**' factor]

power :: { ExprSpan }
power : atom many0(trailer) opt(pair(exponent_op, factor)) 
        { makeBinOp (addTrailer $1 $2) (maybeToList $3) } 

exponent_op :: { OpSpan }
exponent_op: '**' { AST.Exponent (getSpan $1) }

{-
   atom: ('(' [yield_expr|testlist_gexp] ')' |
       '[' [listmaker] ']' |
       '{' [dictorsetmaker] '}' |
       '`' testlist1 '`' |
       NAME | NUMBER | STRING+)
-}

atom :: { ExprSpan }
atom 
   : '(' yield_or_testlist_gexp ')' { $2 (spanning $1 $3) } 
   | list_atom                      { $1 }
   | dict_or_set_atom               { $1 }
   | '`' testlist1 '`'              { AST.StringConversion $2 (spanning $1 $3) }
   | NAME                           { AST.Var $1 (getSpan $1) }
   | 'integer'                      { AST.Int (token_integer $1) (token_literal $1) (getSpan $1) }
   | 'long_integer'                 { AST.LongInt (token_integer $1) (token_literal $1) (getSpan $1) }
   | 'float'                        { AST.Float (token_double $1) (token_literal $1) (getSpan $1) }
   | 'imaginary'                    { AST.Imaginary (token_double $1) (token_literal $1) (getSpan $1) }
   | many1('string')                { AST.Strings (map token_literal $1) (getSpan $1) }
   | many1('bytestring')            { AST.ByteStrings (map token_literal $1) (getSpan $1) }
   | many1('unicodestring')         { AST.UnicodeStrings (map token_literal $1) (getSpan $1) }

-- listmaker: test ( list_for | (',' test)* [','] )

list_atom :: { ExprSpan }
list_atom
   : '[' ']' { List [] (spanning $1 $2) }
   | '[' testlistfor ']' { makeListForm (spanning $1 $3) $2 }

dict_or_set_atom :: { ExprSpan }
dict_or_set_atom
   : '{' '}' { Dictionary [] (spanning $1 $2) }
   | '{' dictorsetmaker '}' { $2 (spanning $1 $3) }

testlistfor :: { Either ExprSpan ComprehensionSpan }
testlistfor
   : testlist { Left $1 }
   | test list_for { Right (makeComprehension $1 $2) }

yield_or_testlist_gexp :: { SrcSpan -> ExprSpan }
yield_or_testlist_gexp
   : {- empty -} { Tuple [] }
   | yield_expr { Paren $1 }
   | testlist_gexp { either Paren Generator $1 } 

-- testlist_gexp: test ( gen_for | (',' test)* [','] )

testlist_gexp :: { Either ExprSpan ComprehensionSpan }
testlist_gexp
   : testlist { Left $1 }
   | test gen_for { Right (makeComprehension $1 $2) }

-- trailer: '(' [arglist] ')' | '[' subscriptlist ']' | '.' NAME 

trailer :: { Trailer }
trailer 
   : paren_arg_list { TrailerCall $1 (getSpan $1) }
   | '[' subscriptlist ']' { TrailerSubscript $2 (spanning $1 $3) } 
   | '.' NAME { TrailerDot $2 (getSpan $1) (spanning $1 $2) }

-- subscriptlist: subscript (',' subscript)* [',']

subscriptlist :: { [Subscript] }
subscriptlist : sepOptEndBy(subscript, ',') { $1 }

-- subscript: '.' '.' '.' | test | [test] ':' [test] [sliceop]

subscript :: { Subscript }
subscript
   : '.' '.' '.' { SubscriptSliceEllipsis (spanning $1 $3) }
   | test { SubscriptExpr $1 (getSpan $1) }
   | opt(test) ':' opt(test) opt(sliceop) 
     { SubscriptSlice $1 $3 $4 (spanning (spanning (spanning $1 $2) $3) $4) }

-- sliceop: ':' [test]

sliceop :: { Maybe ExprSpan }
sliceop : ':' opt(test) { $2 }

-- exprlist: expr (',' expr)* [',']

exprlist :: { [ExprSpan] }
exprlist: sepOptEndBy(expr, ',') { $1 }

opt_comma :: { Maybe Token }
opt_comma 
   : {- empty -} { Nothing }
   | ','         { Just $1 }  

-- testlist: test (',' test)* [',']

-- Some trickery here because the of the optional trailing comma, which
-- could turn a normal expression into a tuple.
-- Very occasionally, testlist is used to generate something which is not
-- a tuple (such as the square bracket notation in list literals). Therefore
-- it would seem like a good idea to not return a tuple in this case, but
-- a list of expressions. However this would complicate a lot of code
-- since we would have to carry around the optional comma information.
-- I've decided to leave it as a tuple, and in special cases, unpack the
-- tuple and pull out the list of expressions.

testlist :: { ExprSpan }
testlist : testlistrev opt_comma { makeTupleOrExpr (reverse $1) $2 }

testlistrev :: { [ExprSpan] }
testlistrev
   : test { [$1] }
   | testlistrev ',' test { $3 : $1 }

{-
   dictorsetmaker: ( (test ':' test (comp_for | (',' test ':' test)* [','])) |
                   (test (comp_for | (',' test)* [','])) )
-}

dictorsetmaker :: { SrcSpan -> ExprSpan }
dictorsetmaker
   : test ':' test dict_rest { makeDictionary ($1, $3) $4 }
   | test set_rest { makeSet $1 $2 }

dict_rest :: { Either CompForSpan [(ExprSpan, ExprSpan)] }
dict_rest
   : comp_for { Left $1 }
   | zero_or_more_dict_mappings_rev opt_comma { Right (reverse $1) }

zero_or_more_dict_mappings_rev :: { [(ExprSpan, ExprSpan)] }
zero_or_more_dict_mappings_rev
   : {- empty -} { [] }
   | zero_or_more_dict_mappings_rev ',' test ':' test { ($3,$5) : $1 }

set_rest :: { Either CompForSpan [ExprSpan] }
set_rest
   : comp_for { Left $1 }
   | zero_or_more_comma_test_rev opt_comma { Right (reverse $1) }

zero_or_more_comma_test_rev :: { [ExprSpan] }
zero_or_more_comma_test_rev
   : {- empty -} { [] }
   | zero_or_more_comma_test_rev ',' test { $3 : $1 }

-- classdef: 'class' NAME ['(' [testlist] ')'] ':' suite

classdef :: { StatementSpan }
classdef 
   : 'class' NAME optional_paren_testlist ':' suite 
     { AST.Class $2 $3 $5 (spanning $1 $5) }

optional_paren_testlist :: { [ArgumentSpan] }
optional_paren_testlist
   : {- empty -} { [] }
   | '(' ')' { [] }
   | '(' testlistrev opt_comma ')' 
     { map (\e -> ArgExpr e (getSpan e)) (reverse $2) }

optional_arg_list :: { [ArgumentSpan] }
optional_arg_list: opt(arglist) { concat (maybeToList $1) } 

{- 
   arglist: (argument ',')* (argument [',']
                         |'*' test (',' argument)* [',' '**' test]
                         |'**' test)
-}

{-
   We don't follow the grammar rules directly (though we do implement
   something equivalent). The reason is that there is ambiguity over
   the optional comma.

   It is probably okay to allow the optional comma even after the *, and
   ** forms. It seems more consistent to me.
-}

arglist :: { [ArgumentSpan] }
arglist: sepOptEndBy(oneArgument,',') {% checkArguments $1 }

oneArgument
   : '*' test { ArgVarArgsPos  $2 (spanning $1 $2) }
   | '**' test { ArgVarArgsKeyword $2 (spanning $1 $2) }
   | argument { $1 }

-- argument: test [gen_for] | test '=' test

argument :: { ArgumentSpan }
argument
   : NAME '=' test { ArgKeyword $1 $3 (spanning $1 $3) }
   | test { ArgExpr $1 (getSpan $1) } 
   | test gen_for 
     { let span = spanning $1 $1 in ArgExpr (Generator (makeComprehension $1 $2) span) span }

-- comp_iter: comp_for | comp_if

comp_iter :: { CompIterSpan }
comp_iter
   : comp_for { IterFor $1 (getSpan $1) }
   | comp_if  { IterIf $1 (getSpan $1) }

-- comp_for: 'for' exprlist 'in' or_test [comp_iter]

comp_for :: { CompForSpan }
comp_for
   : 'for' exprlist 'in' or_test opt(comp_iter)
     { CompFor $2 $4 $5 (spanning (spanning $1 $4) $5) }

-- comp_if: 'if' old_trest [comp_iter]

comp_if :: { CompIfSpan }
comp_if
   : 'if' old_test opt(comp_iter)
     { CompIf $2 $3 (spanning (spanning $1 $2) $3) }

-- list_iter: list_for | list_if
list_iter :: { CompIterSpan }
list_iter
   : list_for { AST.IterFor $1 (getSpan $1) }
   | list_if { AST.IterIf $1 (getSpan $1) }

-- list_for: 'for' exprlist 'in' testlist_safe [list_iter]
list_for :: { CompForSpan }
list_for: 'for' exprlist 'in' testlist_safe opt(list_iter)
          { AST.CompFor $2 $4 $5 (spanning (spanning $1 $4) $5) }

-- list_if: 'if' old_test [list_iter]

list_if :: { CompIfSpan }
list_if: 'if' old_test opt(list_iter) { AST.CompIf $2 $3 (spanning (spanning $1 $2) $3) }

-- gen_iter: gen_for | gen_if

gen_iter :: { CompIterSpan }
gen_iter
   : gen_for { AST.IterFor $1 (getSpan $1) }
   | gen_if { AST.IterIf $1 (getSpan $1) }

-- gen_for: 'for' exprlist 'in' or_test [gen_iter]

gen_for :: { CompForSpan }
gen_for: 'for' exprlist 'in' or_test opt(gen_iter)
          { AST.CompFor $2 $4 $5 (spanning (spanning $1 $4) $5) }

-- gen_if: 'if' old_test [gen_iter]

gen_if :: { CompIfSpan }
gen_if: 'if' old_test opt(gen_iter) { AST.CompIf $2 $3 (spanning (spanning $1 $2) $3) }

-- testlist1: test (',' test)*

testlist1 :: { ExprSpan }
testlist1: sepBy(test, ',') { makeTupleOrExpr $1 Nothing }

-- encoding_decl: NAME
-- Not used in the rest of the grammar!

-- yield_expr: 'yield' [testlist] 

yield_expr :: { ExprSpan }
yield_expr : 'yield' optional_yieldarg { AST.Yield $2 (spanning $1 $2) }

optional_testlist :: { Maybe ExprSpan }
optional_testlist: opt(testlist) { $1 }

optional_yieldarg :: { Maybe YieldArgSpan }
optional_yieldarg : opt(yieldarg) { $1 }

yieldarg :: { YieldArgSpan }
yieldarg: testlist { YieldExpr $1 }

{
-- Put additional Haskell code in here if needed.
}
