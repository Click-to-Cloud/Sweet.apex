{
  function extractOptional(optional, index, def) {
    def = typeof def !== 'undefined' ?  def : null;
    return optional ? optional[index] : def;
  }

  function extractList(list, index) {
    var result = new Array(list.length), i;

    for (i = 0; i < list.length; i++) {
      result[i] = list[i][index];
    }

    return result;
  }

  function buildList(first, rest, index) {
    var list = [first].concat(extractList(rest, index));
    var newList = [];
    for(var i = 0; i < list.length; i++) {
        if(list[i]) {
            newList.push(list[i]);
        }
    }

    return newList;
  }

  function buildTree(first, rest, builder) {
    var result = first, i;

    for (i = 0; i < rest.length; i++) {
      result = builder(result, rest[i]);
    }

    return result;
  }

  function buildInfixExpr(first, rest) {
    return buildTree(first, rest, function(result, element) {
      return {
        node:        'InfixExpression',
        operator:     element[0][0], // remove ending Spacing
        leftOperand:  result,
        rightOperand: element[1]
      };
    });
  }

    function buildQualified(first, rest, index) {
        return buildTree(first, rest,
            function(result, element) {
                return {
                    node:     'QualifiedName',
                    qualifier: result,
                    name:      element[index]
                };
            }
        );
    }

  function popQualified(tree) {
      if(tree.node === 'QualifiedName') {
          return {
              name: tree.name,
              expression: tree.qualifier,
          };
      }
      else {
          return {
              name: tree,
              expression: null,
          };
      }
  }

  function extractExpressions(list) {
    return list.map(function(node) {
      return node.expression;
    });
  }

  function buildArrayTree(first, rest) {
    return buildTree(first, rest,
      function(result, element) {
      return {
        node:         'ArrayType',
        componentType: result
      };
    });
  }

  function optionalList(value) {
    return value !== null ? value : [];
  }

  function extractOptionalList(list, index) {
    return optionalList(extractOptional(list, index));
  }

  function skipNulls(list) {
    return list.filter(function(v){ return v !== null; });
  }

  function makePrimitive(code) {
    return {
      node:             'PrimitiveType',
      primitiveTypeCode: code
    }
  }

  function makeModifier(keyword) {
    return {
      node:   'Modifier',
      keyword: keyword
    };
  }

  function makeCatchFinally(catchClauses, finallyBlock) {
      return {
        catchClauses: catchClauses,
        finally:      finallyBlock
      };
  }

  function buildTypeName(qual, args, rest) {
    var first = args === null ? {
      node: 'SimpleType',
      name:  qual
    } : {
      node: 'ParameterizedType',
      type:  {
          node: 'SimpleType',
          name:  qual
      },
      typeArguments: args
    };

    return buildTree(first, rest,
      function(result, element) {
        var args = element[2];
        return args === null ? {
          node:     'QualifiedType',
          name:      element[1],
          qualifier: result
        } :
        {
          node: 'ParameterizedType',
          type:  {
            node:     'QualifiedType',
            name:      element[1],
            qualifier: result
          },
          typeArguments: args
        };
      }
    );
  }

  function mergeProps(obj, props) {
    var key;
    for (key in props) {
      if (props.hasOwnProperty(key)) {
        if (obj.hasOwnProperty(key)) {
          throw new Error(
            'Property ' + key + ' exists ' + line() + '\n' + text() +
            '\nCurrent value: ' + JSON.stringify(obj[key], null, 2) +
            '\nNew value: ' + JSON.stringify(props[key], null, 2)
          );
        } else {
          obj[key] = props[key];
        }
      }
    }
    return obj;
  }

  function buildSelectorTree(arg, sel, sels) {
    function getMergeVal(o,v) {
      switch(o.node){
        case 'SuperFieldAccess':
        case 'SuperMethodInvocation':
          return { qualifier: v };
        case 'ArrayAccess':
          return { array: v };
        default:
          return { expression: v };
      }
    }
    return buildTree(mergeProps(sel, getMergeVal(sel, arg)),
      sels, function(result, element) {
        return mergeProps(element, getMergeVal(element, result));
    });
  }

  function leadingComments(comments) {
    const leadComments = [];

    for(var i = 0; i < comments.length; i++) {
      leadComments.push({
        ast_type: "comment",
        value: comments[i].value,
        leading: true,
        trailing: false,
        printed: false
      });
    }

    return leadComments;
  }

  function TODO() {
    throw new Error('TODO: not impl line ' + line() + '\n' + text());
  }
}

/* ---- Syntactic Grammar ----- */

//-------------------------------------------------------------------------
//  Compilation Unit
//-------------------------------------------------------------------------

CompilationUnit
    = Spacing imports:ImportDeclaration* types:TypeDeclaration* EmptyLines EOT
    {
      return {
        node:    'CompilationUnit',
        types:    skipNulls(types),
        imports:  skipNulls(imports)
      };
    }

ImportDeclaration
    = EmptyLines IMPORT stat:STATIC? name:QualifiedIdentifier alias:(AS Identifier)? SEMI
    {
      return {
        node:    'ImportDeclaration',
        name:     name,
        static:   !!stat,
        alias:    extractOptional(alias, 1)
      };
    }
    / SEMI
    { return null; }

TypeDeclaration
    = EmptyLines
      leadComments:LeadingComments
      EmptyLines
      modifiers:Modifier*
      EmptyLines
      type:(
          ClassDeclaration
        / InterfaceDeclaration
        / EnumDeclaration
        / AnnotationTypeDeclaration
      )
      { return mergeProps(type, { modifiers: modifiers, comments: leadComments }); }
      / SEMI
      { return null; }

//-------------------------------------------------------------------------
//  Class Declaration
//-------------------------------------------------------------------------

ClassDeclaration
    = CLASS id:Identifier EmptyLines gen:TypeParameters? EmptyLines ext:(EXTENDS ClassType)? EmptyLines impl:(IMPLEMENTS ClassTypeList)? EmptyLines body:ClassBody
    {
      return {
        node:               'TypeDeclaration',
        name:                id,
        superInterfaceTypes: extractOptionalList(impl, 1),
        superclassType:      extractOptional(ext, 1),
        bodyDeclarations:    body,
        typeParameters:      optionalList(gen),
        interface:           false
      };
    }

ClassBody
    = LWING decls:ClassBodyDeclaration* Indent RWING
    { return skipNulls(decls); }

ClassBodyDeclaration
    = Indent SEMI
    { return null; }
    / Indent modifier:STATIC? body:Block                      // Static or Instance Initializer
    {
      return {
        node:     'Initializer',
        body:      body,
        modifiers: modifier === null ? [] : [makeModifier('static')]
      };
    }
    / Indent first:Modifier? rest:(EmptyLines NonJavaDocComment? Modifier)* EmptyLines (EmptyLines NonJavaDocComment)* member:MemberDecl            // ClassMemberDeclaration
    { return mergeProps(member, { modifiers: buildList(first, rest, 2) }); }
    / Indent comment:EndOfLineComment
    { return { node: "EndOfLineComment", comment: comment.value }; }
    / Indent comment:TraditionalComment
    { return { node: "TraditionalComment", comment: comment.value }; }
    / Indent comment:JavaDocComment
    { return { node: "JavaDocComment", comment: comment.value }; }
    / Indent !LetterOrDigit [\r\n\u000C]
    { return { node: "LineEmpty" }; }

MemberDecl
    = InterfaceDeclaration                             // Interface
    / ClassDeclaration                                 // Class
    / EnumDeclaration                                  // Enum
    / AnnotationTypeDeclaration                        // Annotation
    / EmptyLines type:Type EmptyLines id:Identifier
      rest:MethodDeclaratorRest                        // Method
    {
      return mergeProps(rest, {
        node:          'MethodDeclaration',
        returnType2:    type,
        name:           id,
        typeParameters: []
      });
    }
    / type:Type decls:VariableDeclarators SEMI?         // Field
    {
      return {
        node:     'FieldDeclaration',
        fragments: decls,
        type:      type
      };
    }
    / EmptyLines VOID EmptyLines id:Identifier rest:VoidMethodDeclaratorRest // Void method
    {
      return mergeProps(rest, {
        node:       'MethodDeclaration',
        returnType2: makePrimitive('void'),
        name:        id,
        constructor: false
      });
    }
    / id:Identifier rest:ConstructorDeclaratorRest     // Constructor
    {
      return mergeProps(rest, {
        node:           'MethodDeclaration',
        name:            id,
        typeParameters:  []
      });
    }

MethodDeclaratorRest
    = EmptyLines (EmptyLines NonJavaDocComment)* params:FormalParameters dims:Dim*
      body:(MethodBody / SEMI { return null; })
    {
      return {
        parameters:       params,
        extraDimensions:  dims.length,
        body:             body,
        constructor:      false
      };
    }

VoidMethodDeclaratorRest
    = EmptyLines (EmptyLines NonJavaDocComment)* params:FormalParameters
      body:(MethodBody / SEMI { return null; })
    {
      return {
        parameters:       params,
        body:             body,
        extraDimensions:  0,
        typeParameters:   []
      };
    }

ConstructorDeclaratorRest
    = EmptyLines (EmptyLines NonJavaDocComment)* params:FormalParameters body:MethodBody
    {
      return {
        parameters:       params,
        body:             body,
        returnType2:      null,
        constructor:      true,
        extraDimensions:  0
      };
    }

MethodBody
    = Block

//-------------------------------------------------------------------------
//  Interface Declaration
//-------------------------------------------------------------------------

InterfaceDeclaration
    = INTERFACE id:Identifier gen:TypeParameters? ext:(EXTENDS ClassTypeList)? body:InterfaceBody
    {
      return {
          node:               'TypeDeclaration',
          name:                id,
          superInterfaceTypes: extractOptionalList(ext, 1),
          superclassType:      null,
          bodyDeclarations:    body,
          typeParameters:      optionalList(gen),
          interface:           true
        };
    }

InterfaceBody
    = EmptyLines LWING decls:InterfaceBodyDeclaration* Indent RWING
    { return skipNulls(decls); }

InterfaceBodyDeclaration
    = Indent modifiers:Modifier* member:InterfaceMemberDecl
    { return mergeProps(member, { modifiers: modifiers }); }
    / Indent SEMI
    { return null; }
    / Indent comment:EndOfLineComment
    { return { node: "EndOfLineComment", comment: comment.value }; }
    / Indent comment:TraditionalComment
    { return { node: "TraditionalComment", comment: comment.value }; }
    / Indent comment:JavaDocComment
    { return { node: "JavaDocComment", comment: comment.value }; }
    / Indent !LetterOrDigit [\r\n\u000C]
    { return { node: "LineEmpty" }; }

InterfaceMemberDecl
    = InterfaceDeclaration
    / ClassDeclaration
    / EnumDeclaration
    / InterfaceMethodOrFieldDecl
    / InterfaceGenericMethodDecl
    / VOID id:Identifier rest:VoidInterfaceMethodDeclaratorRest
    { return mergeProps(rest, { name: id }); }

InterfaceMethodOrFieldDecl
    = type:Type id:Identifier rest:InterfaceMethodOrFieldRest
    {
      if (rest.node === 'FieldDeclaration') {
        rest.fragments[0].name = id;
        return mergeProps(rest, { type: type });
      } else {
        return mergeProps(rest, {
          returnType2:    type,
          name:           id,
          typeParameters: []
        });
      }
    }

InterfaceMethodOrFieldRest
    = rest:ConstantDeclaratorsRest SEMI
    { return { node: 'FieldDeclaration', fragments: rest }; }
    / InterfaceMethodDeclaratorRest

InterfaceMethodDeclaratorRest
    = params:FormalParameters dims:Dim* SEMI
    {
      return {
        node:            'MethodDeclaration',
        parameters:       params,
        extraDimensions:  dims.length,
        body:             null,
        constructor:      false
      };
    }

InterfaceGenericMethodDecl
    = params:TypeParameters type:(Type / VOID { return makePrimitive('void'); }) id:Identifier rest:InterfaceMethodDeclaratorRest
    {
      return mergeProps(rest, {
        returnType2:    type,
        name:           id,
        typeParameters: params
      });
    }

VoidInterfaceMethodDeclaratorRest
    = params:FormalParameters SEMI
    {
      return {
        node:            'MethodDeclaration',
        parameters:       params,
        returnType2:      makePrimitive('void'),
        extraDimensions:  0,
        typeParameters:   [],
        body:             null,
        constructor:      false
      };
    }

ConstantDeclaratorsRest
    = first:ConstantDeclaratorRest rest:(COMMA ConstantDeclarator)*
    { return buildList(first, rest, 1); }

ConstantDeclarator
    = id:Identifier rest:ConstantDeclaratorRest
    {
        return mergeProps(rest, { name: id });
    }

ConstantDeclaratorRest
    = dims:Dim* EQU init:VariableInitializer
    {
        return {
          node:           'VariableDeclarationFragment',
          extraDimensions: dims.length,
          initializer:     init
      };
    }

//-------------------------------------------------------------------------
//  Enum Declaration
//-------------------------------------------------------------------------

EnumDeclaration
    = ENUM name:Identifier impl:(IMPLEMENTS ClassTypeList)? eb:EnumBody
    {
      return mergeProps(eb, {
        node:               'EnumDeclaration',
        name:                name,
        superInterfaceTypes: extractOptionalList(impl, 1)
      });
    }

EnumBody
    = LWING consts:EnumConstants? COMMA? body:EnumBodyDeclarations? Indent RWING
    {
      return {
        enumConstants:    optionalList(consts),
        bodyDeclarations: optionalList(body)
      };
    }

EnumConstants
    = first:EnumConstant rest:(COMMA EnumConstant)*
    { return buildList(first, rest, 1); }

EnumConstant
    = EmptyLines annot:Annotation* name:Identifier args:Arguments? cls:ClassBody?
    {
        return {
            node:                     'EnumConstantDeclaration',
            anonymousClassDeclaration: cls === null ? null : {
                node:             'AnonymousClassDeclaration',
                bodyDeclarations:  cls
            },
            arguments:                 optionalList(args),
            modifiers:                 annot,
            name:                      name
        };
    }

EnumBodyDeclarations
    = SEMI decl:ClassBodyDeclaration*
    { return decl; }

//-------------------------------------------------------------------------
//  Variable Declarations
//-------------------------------------------------------------------------

LocalVariableDeclarationStatement
    = Indent modifiers:(FINAL { return makeModifier('final'); } / Annotation)*
      type:Type decls:VariableDeclarators SEMI
    {
      return {
        node:        'VariableDeclarationStatement',
        fragments:    decls,
        modifiers:    modifiers,
        type:         type
      };
    }
    / Indent type:Type? variables:Destructure EmptyLines init:(EQU VariableInitializer)? SEMI
    {
        return {
            node: 'DestructureStatement',
            type: type,
            variables: variables,
            initializer: extractOptional(init, 1),
        };
    }

Destructure
    = EmptyLines LWING
      init:(
        first:DestructurePair rest:(COMMA DestructurePair)*
        { return buildList(first, rest, 1); }
      )?
      EmptyLines  RWING
    { return { node: 'Destructure', expressions: optionalList(init) }; }

DestructurePair
    = Indent name:Identifier rename:DestructureRename?
    {
        return {
            node: 'DestructurePair',
            name: name,
            rename: rename,
        };
    }

DestructureRename
    = Indent COLON type:Type name:Identifier? defaultValue:(EQU VariableInitializer)?
    {
        return {
            node: 'DestructureRename',
            name: name,
            type: type,
            defaultValue: extractOptional(defaultValue, 1),
        };
    }

VariableDeclarators
    = first:VariableDeclarator rest:(COMMA VariableDeclarator)*
    { return buildList(first, rest, 1); }

VariableDeclarator
    = name:Identifier dims:Dim* EmptyLines init:(EQU VariableInitializer)? accessor:(AccessorDeclarator1 / AccessorDeclarator2)?
    {
        return {
            node:           'VariableDeclarationFragment',
            name:            name,
            extraDimensions: dims.length,
            initializer:     extractOptional(init, 1),
            accessor:        accessor
        };
    }

SetterDeclarator
    = modifiers:Modifier* Indent SET body:Block? Indent SEMI?
    {
        return {
            modifiers: modifiers,
            body: body,
        };
    }

GetterDeclarator
    = modifiers:Modifier* Indent GET body:Block? Indent SEMI?
    {
        return {
            modifiers: modifiers,
            body: body,
        };
    }

AccessorDeclarator1
    = LWING
    setter:SetterDeclarator?
    EmptyLines
    getter:GetterDeclarator?
    EmptyLines RWING
    {
        return {
            node: 'AccessorDeclarationFragment',
            setter: setter,
            getter: getter,
        };
    }

AccessorDeclarator2
    = LWING
    getter:GetterDeclarator?
    EmptyLines
    setter:SetterDeclarator?
    EmptyLines RWING
    {
        return {
            node: 'AccessorDeclarationFragment',
            setter: setter,
            getter: getter,
        };
    }

//-------------------------------------------------------------------------
//  Formal Parameters
//-------------------------------------------------------------------------

FormalParameters
    = LPAR params:FormalParameterList? EmptyLines RPAR
    { return optionalList(params); }

FormalParameter
    = EmptyLines modifiers:(FINAL { return makeModifier('final'); } / Annotation)*
      type:Type decl:VariableDeclaratorId
    {
      return mergeProps(decl, {
        type:        type,
        modifiers:   modifiers,
        varargs:     false,
        initializer: null
      });
    }

LastFormalParameter
    = modifiers:(FINAL { return makeModifier('final'); } / Annotation)*
      type:Type ELLIPSIS decl:VariableDeclaratorId
    {
      return mergeProps(decl, {
        type:        type,
        modifiers:   modifiers,
        varargs:     true,
        initializer: null
      });
    }

FormalParameterList
    = first:FormalParameter rest:(COMMA FormalParameter)* last:(COMMA LastFormalParameter)?
    { return buildList(first, rest, 1).concat(extractOptionalList(last, 1)); }
    / last:LastFormalParameter
    { return [last]; }

VariableDeclaratorId
    = id:Identifier required:BANG? optional:QUERY? defaultValue:(EQU ElementValue)? dims:Dim*
    {
        return {
            node:           'SingleVariableDeclaration',
            name:            id,
            extraDimensions: dims.length,
            required:        required,
            optional:        optional,
            defaultValue:    defaultValue && defaultValue[1],
        };
    }

//-------------------------------------------------------------------------
//  Statements
//-------------------------------------------------------------------------

Block
    = Indent LWING statements:BlockStatements Indent RWING
    {
      return {
        node:      'Block',
        statements: statements
      }
    }

BlockStatements
    = BlockStatement*

BlockStatement
    = Indent !LetterOrDigit [\r\n\u000C]
    { return { node: "LineEmpty" }; }
    / Indent comment:EndOfLineComment
    { return { node: "EndOfLineComment", comment: comment.value }; }
    / Indent comment:TraditionalComment
    { return { node: "TraditionalComment", comment: comment.value }; }
    / Indent comment:JavaDocComment
    { return { node: "JavaDocComment", comment: comment.value }; }
    / Indent op:DMLOperator Indent operand:Expression Indent rest:Expression? SEMI
    {
        return {
            node: 'DMLStatement',
            operator: op[1],
            operand: operand,
            rest: rest,
        };
    }
    / LocalVariableDeclarationStatement
    / Indent modifiers:Modifier* decl:( ClassDeclaration / EnumDeclaration )
    {
      return {
        node:       'TypeDeclarationStatement',
        declaration: mergeProps(decl,  { modifiers: modifiers })
      };
    }
    / Statement

Statement
    = Block
    / BlockExpressionStatement
    / Indent IF expr:ParExpression EmptyLines (EmptyLines NonJavaDocComment)* then:Statement EmptyLines (EmptyLines NonJavaDocComment)* alt:(ELSE Statement)?
    {
      return {
        node:         'IfStatement',
        elseStatement: extractOptional(alt, 1),
        thenStatement: then,
        expression:    expr.expression,
      };
    }
    / Indent FOR LPAR EmptyLines (EmptyLines NonJavaDocComment)* init:ForInit? SEMI EmptyLines (EmptyLines NonJavaDocComment)* expr:Expression? SEMI EmptyLines (EmptyLines NonJavaDocComment)* up:ForUpdate? RPAR body:Statement
    {
      return {
        node:        'ForStatement',
        initializers: optionalList(init),
        expression:   expr,
        updaters:     optionalList(up),
        body:         body
      };
    }
    / Indent FOR LPAR param:FormalParameter COLON expr:Expression RPAR statement:Statement
    {
      return {
        node:      'EnhancedForStatement',
        parameter:  param,
        expression: expr,
        body:       statement
      };
    }
    / Indent WHILE expr:ParExpression body:Statement
    {
      return {
        node:      'WhileStatement',
        expression: expr.expression,
        body:       body
      };
    }
    / Indent DO statement:Statement WHILE expr:ParExpression SEMI
    {
      return {
        node:      'DoStatement',
        expression: expr.expression,
        body:       statement
      };
    }
    / Indent TRY body:Block
      rest:(cat:Catch+ fin:Finally? { return makeCatchFinally(cat, fin); }
            / fin:Finally { return makeCatchFinally([], fin); })
    {
      return mergeProps(rest, {
        node:        'TryStatement',
        body:         body,
        resources:    []
      });
    }
    / Indent SWITCH expr:ParExpression LWING cases:SwitchBlockStatementGroups EmptyLines RWING
    { return { node: 'SwitchStatement', statements: cases, expression: expr.expression }; }
    / Indent RETURN expr:Expression? SEMI
    { return { node: 'ReturnStatement', expression: expr } }
    / Indent THROW expr:Expression SEMI
    { return { node: 'ThrowStatement', expression: expr }; }
    / Indent BREAK id:Identifier? SEMI
    { return { node: 'BreakStatement', label: id }; }
    / Indent CONTINUE id:Identifier? SEMI
    { return { node: 'ContinueStatement', label: id }; }
    / Indent SEMI
    { return { node: 'EmptyStatement' }; }
    / Indent statement:StatementExpression SEMI
    { return statement; }
    / Indent id:Identifier COLON statement:Statement
    { return { node: 'LabeledStatement', label: id, body: statement }; }
    / Indent !LetterOrDigit [\r\n\u000C]
    { return { node: "LineEmpty" }; }

Catch
    = CATCH LPAR modifiers:(FINAL { return makeModifier('final'); } / Annotation)*
      first:Type rest:(OR Type)* decl:VariableDeclaratorId EmptyLines RPAR body:Block
    {
      return {
        node:       'CatchClause',
        body:        body,
        exception:   mergeProps(decl, {
          modifiers:   modifiers,
          initializer: null,
          varargs:     false,
          type:        rest.length ? {
            node: 'UnionType',
            types: buildList(first, rest, 1)
            } : first
        })
      };
    }

Finally
    = FINALLY block:Block
    { return block; }

BlockExpressionStatement
    = expr:Expression body:Block
    {
        return {
            node: 'BlockExpressionStatement',
            expression: expr,
            body: body,
        };
    }

SwitchBlockStatementGroups
    = blocks:SwitchBlockStatementGroup*
    { return [].concat.apply([], blocks); }

SwitchBlockStatementGroup
    = expr:SwitchLabel blocks:BlockStatements
    { return [{ node: 'SwitchCase', expression: expr }].concat(blocks); }

SwitchLabel
    = CASE expr:ConstantExpression COLON
    { return expr; }
    / CASE expr:EnumConstantName COLON
    { return expr; }
    / DEFAULT COLON
    { return null; }

ForInit
    = modifiers:(FINAL { return makeModifier('final'); } / Annotation)* type:Type decls:VariableDeclarators
    {
      return [{
        node:     'VariableDeclarationExpression',
        modifiers: modifiers,
        fragments: decls,
        type:      type
      }];
    }
    / first:StatementExpression rest:(COMMA StatementExpression)*
    { return extractExpressions(buildList(first, rest, 1)); }

ForUpdate
    = first:StatementExpression rest:(COMMA StatementExpression)*
    { return extractExpressions(buildList(first, rest, 1)); }

EnumConstantName
    = Identifier

//-------------------------------------------------------------------------
//  Expressions
//-------------------------------------------------------------------------

StatementExpression
    = expr:Expression
    {
      switch(expr.node) {
        case 'SuperConstructorInvocation':
        case 'ConstructorInvocation':
          return expr;
        default:
          return {
            node:      'ExpressionStatement',
            expression: expr
          };
      }
    }

ConstantExpression
    = Expression

MethodReference
    = left:Identifier COLONCOLON right:(Identifier / NEW { return { node: "SimpleName", identifier: "new" }; })
    {
      return {
        node: 'MethodReference',
        class: left,
        method: right
      };
    }

Expression
    = left:ConditionalExpression op:AssignmentOperator right:Expression
    {
      return {
        node:         'Assignment',
        operator:      op[0] /* remove ending spaces */,
        leftHandSide:  left,
        rightHandSide: right
      };
    }
    / MethodReference
    / LambdaExpression
    / ConditionalExpression

LambdaExpression
    = args:FormalParameters POINTER body:LambdaBody
    {
      return {
        node: 'LambdaExpression',
        args: args,
        body: body
      };
    }

LambdaBody
    = body:MethodBody
    { return body; }

AssignmentOperator
    = EQU
    / PLUSEQU
    / MINUSEQU
    / STAREQU
    / DIVEQU
    / ANDEQU
    / OREQU
    / HATEQU
    / MODEQU
    / SLEQU
    / SREQU
    / BSREQU

DMLOperator
    = INSERT
    / UPDATE
    / UPSERT
    / DELETE
    / UNDELETE
    / MERGE

ConditionalExpression
    = expr:ConditionalOrExpression QUERY then:Expression COLON alt:ConditionalExpression
    {
      return {
        node:          'ConditionalExpression',
        expression:     expr,
        thenExpression: then,
        elseExpression: alt
      };
    }
    / ConditionalOrExpression

ConditionalOrExpression
    = EmptyLines (EmptyLines NonJavaDocComment)* EmptyLines first:ConditionalAndExpression EmptyLines (EmptyLines NonJavaDocComment)* EmptyLines rest:(OROR ConditionalAndExpression)*
    { return buildInfixExpr(first, rest); }

ConditionalAndExpression
    = EmptyLines (EmptyLines NonJavaDocComment)* EmptyLines first:PipelineExpression EmptyLines (EmptyLines NonJavaDocComment)* EmptyLines rest:(ANDAND PipelineExpression)*
    { return buildInfixExpr(first, rest); }

PipelineExpression
    = EmptyLines (EmptyLines NonJavaDocComment)* EmptyLines first:InclusiveOrExpression EmptyLines (EmptyLines NonJavaDocComment)* EmptyLines rest:(PIPE InclusiveOrExpression)*
    { return buildInfixExpr(first, rest); }

InclusiveOrExpression
    = EmptyLines (EmptyLines NonJavaDocComment)* EmptyLines first:ExclusiveOrExpression EmptyLines (EmptyLines NonJavaDocComment)* EmptyLines rest:(OR ExclusiveOrExpression)*
    { return buildInfixExpr(first, rest); }

ExclusiveOrExpression
    = EmptyLines (EmptyLines NonJavaDocComment)* EmptyLines first:AndExpression EmptyLines (EmptyLines NonJavaDocComment)* EmptyLines rest:(HAT AndExpression)*
    { return buildInfixExpr(first, rest); }

AndExpression
    = EmptyLines (EmptyLines NonJavaDocComment)* EmptyLines first:EqualityExpression EmptyLines (EmptyLines NonJavaDocComment)* EmptyLines rest:(AND EqualityExpression)*
    { return buildInfixExpr(first, rest); }

EqualityExpression
    = EmptyLines (EmptyLines NonJavaDocComment)* EmptyLines first:RelationalExpression EmptyLines (EmptyLines NonJavaDocComment)* EmptyLines rest:((EQUAL /  NOTEQUAL) RelationalExpression)*
    { return buildInfixExpr(first, rest); }

RelationalExpression
    = EmptyLines (EmptyLines NonJavaDocComment)* EmptyLines first:ShiftExpression EmptyLines (EmptyLines NonJavaDocComment)* EmptyLines rest:((LE / GE / LT / GT) ShiftExpression / INSTANCEOF ReferenceType )*
    {
      return buildTree(first, rest, function(result, element) {
        return element[0][0] === 'instanceof' ? {
          node:        'InstanceofExpression',
          leftOperand:  result,
          rightOperand: element[1]
        } : {
          node:        'InfixExpression',
          operator:     element[0][0], // remove ending Spacing
          leftOperand:  result,
          rightOperand: element[1]
        };
      });
    }

ShiftExpression
    = EmptyLines (EmptyLines NonJavaDocComment)* EmptyLines first:AdditiveExpression EmptyLines (EmptyLines NonJavaDocComment)* EmptyLines rest:((SL / SR / BSR) AdditiveExpression)*
    { return buildInfixExpr(first, rest); }

AdditiveExpression
    = EmptyLines (EmptyLines NonJavaDocComment)* EmptyLines first:MultiplicativeExpression EmptyLines (EmptyLines NonJavaDocComment)* EmptyLines rest:((PLUS / MINUS) MultiplicativeExpression)*
    { return buildInfixExpr(first, rest); }

MultiplicativeExpression
    = EmptyLines (EmptyLines NonJavaDocComment)* EmptyLines first:BinaryOperatorExpression EmptyLines (EmptyLines NonJavaDocComment)* EmptyLines rest:((STAR / DIV / MOD) BinaryOperatorExpression)*
    { return buildInfixExpr(first, rest); }

BinaryOperatorExpression
    = EmptyLines (EmptyLines NonJavaDocComment)* EmptyLines first:UnaryExpression EmptyLines (EmptyLines NonJavaDocComment)* EmptyLines rest:(BINARY_OPERATOR UnaryExpression)*
    { return buildInfixExpr(first, rest); }

UnaryExpression
    = operator:PrefixOp operand:UnaryExpression
    {
      return operand.node === 'NumberLiteral' && operator === '-' &&
        (operand.token === '9223372036854775808L' ||
         operand.token === '9223372036854775808l' ||
         operand.token === '2147483648')
        ? { node: 'NumberLiteral', token: text() }
        : {
          node:    'PrefixExpression',
          operator: operator,
          operand:  operand
        };
    }
    / UnaryExpressionNotPlusMinus

UnaryExpressionNotPlusMinus
    = expr:CastExpression
    {
      return {
        node:      'CastExpression',
        type:       expr[1],
        expression: expr[4]
      };
    }
    / expr:ArrowCastExpression
    {
      return {
        node:      'ArrowCastExpression',
        fromType:   expr[1],
        toType:     expr[5],
        expression: expr[8]
      };
    }
    / arg:Primary sel:Selector sels:Selector* operator:PostfixOp+
    {
      return operator.length > 1 ? TODO() : {
        node:    'PostfixExpression',
        operator: operator[0],
        operand:  buildSelectorTree(arg, sel, sels)
      };
    }
    / arg:Primary sel:Selector sels:Selector*
    { return buildSelectorTree(arg, sel, sels); }
    / arg:Primary operator:PostfixOp+
    {
      return operator.length > 1 ? TODO() : {
        node:    'PostfixExpression',
        operator: operator[0],
        operand:  arg
      };
    }
    / Primary

CastExpression
    = LPAR PrimitiveType RPAR EmptyLines UnaryExpression
    / LPAR ReferenceType RPAR EmptyLines UnaryExpressionNotPlusMinus

ArrowCastExpression
    = LPAR ReferenceType Indent ARROW Indent ReferenceType RPAR EmptyLines UnaryExpressionNotPlusMinus

Primary
    = ParExpression
    / args:NonWildcardTypeArguments ret:(ExplicitGenericInvocationSuffix
    {
      if (ret.typeArguments.length) return TODO(/* Ugly ! */);
      ret.typeArguments = args;
      return ret;
    }
    / THIS args_r:Arguments
    { return { node: 'ConstructorInvocation', arguments: args_r, typeArguments: [] }; })
    / THIS args:Arguments?
    {
      return args === null ? {
        node:     'ThisExpression',
        qualifier: null
      } : {
        node:         'ConstructorInvocation',
        arguments:     args,
        typeArguments: []
      };
    }
    / SUPER suffix:SuperSuffix
    {
      return suffix.node === 'SuperConstructorInvocation'
        ? suffix
        : mergeProps(suffix, { qualifier: null });
    }
    / Literal
    / ArrayInitializer
    / NEW creator:Creator
    { return creator; }
    / QualifiedIdentifierSuffix
    / qId:QualifiedIdentifier
    {
        return qId;
    }
    / type:BasicType dims:Dim* DOT CLASS
    {
      return {
        node: 'TypeLiteral',
        type:  buildArrayTree(type, dims)
      };
    }
    / VOID DOT CLASS
    {
      return {
        node: 'TypeLiteral',
        type:  makePrimitive('void')
      };
    }
    / LBRK value:(Escape / ![\[\]] _)* RBRK
    {
        return {
            node: 'SoqlLiteral',
            value: text(),
        };
    }

QualifiedIdentifierSuffix
    = qual:QualifiedIdentifier dims:Dim+ DOT CLASS
    {
      return {
        node: 'TypeLiteral',
        type:  buildArrayTree(buildTypeName(qual, null, []), dims)
      };
    }
    / qual:QualifiedIdentifier LBRK expr:Expression RBRK
    { return { node: 'ArrayAccess', array: qual, index: expr }; }
    / qual:QualifiedIdentifier args:Arguments
    {
        var ret = mergeProps(popQualified(qual), {
            node:         'MethodInvocation',
            arguments:     args,
            typeArguments: []
        });

        return ret;
    }
    / qual:QualifiedIdentifier typeArgs:TypeArguments? DOT CLASS
    { return { node: 'TypeLiteral', type: buildTypeName(qual, null, []), typeArguments: typeArgs }; }
    / qual:QualifiedIdentifier DOT ret:ExplicitGenericInvocation
    {
      if (ret.expression) return TODO(/* Ugly ! */);
      ret.expression = qual;
      return ret;
    }
    / qual:QualifiedIdentifier DOT THIS
    { return { node: 'ThisExpression', qualifier: qual }; }
    / qual:QualifiedIdentifier DOT SUPER args:Arguments
    {
      return {
        node:         'SuperConstructorInvocation',
        arguments:     args,
        expression:    qual,
        typeArguments: []
      };
    }
    / qual:QualifiedIdentifier DOT NEW args:NonWildcardTypeArguments? rest:InnerCreator
    { return mergeProps(rest, { expression: qual, typeArguments: optionalList(args) }); }

ExplicitGenericInvocation
    = args:NonWildcardTypeArguments ret:ExplicitGenericInvocationSuffix
    {
      if (ret.typeArguments.length) return TODO(/* Ugly ! */);
      ret.typeArguments = args;
      return ret;
    }

NonWildcardTypeArguments
    = LPOINT first:ReferenceType rest:(COMMA ReferenceType)* RPOINT
    { return buildList(first, rest, 1); }

EmptyWildcardTypeArguments
    = LPOINT RPOINT
    { return []; }

TypeArgumentsOrDiamond
    = LPOINT RPOINT
    { return []; }
    / TypeArguments

NonWildcardTypeArgumentsOrDiamond
    = LPOINT RPOINT
    / NonWildcardTypeArguments

ExplicitGenericInvocationSuffix
    = SUPER suffix:SuperSuffix
    { return suffix; }
    / id:Identifier args:Arguments
    {
        return { node: 'MethodInvocation', arguments: args, name: id, typeArguments: [] };
    }

PrefixOp
    = op:(
      INC
    / DEC
    / BANG
    / TILDA
    / PLUS
    / MINUS
    ) { return op[0]; /* remove ending spaces */ }

PostfixOp
    = op:(
      INC
    / DEC
    ) { return op[0]; /* remove ending spaces */ }

Selector
    = nullable:QUERY? DOT EmptyLines id:Identifier args:Arguments
    {
        return { node: 'MethodInvocation', arguments: args, name: id, typeArguments: [], nullable: nullable };
    }
    / nullable:QUERY? DOT EmptyLines id:Identifier
    { return { node: 'FieldAccess', name: id, nullable: nullable }; }
    / DOT EmptyLines ret:ExplicitGenericInvocation
    { return ret; }
    / DOT EmptyLines THIS
    { return TODO(/* Any sample ? */); }
    / DOT EmptyLines SUPER suffix:SuperSuffix
    { return suffix; }
    / DOT EmptyLines NEW args:NonWildcardTypeArguments? ret:InnerCreator
    { return mergeProps(ret, { typeArguments: optionalList(args) }); }
    / expr:DimExpr
    { return { node: 'ArrayAccess', index: expr }; }

SuperSuffix
    = args:Arguments
    {
      return {
        node:         'SuperConstructorInvocation',
        arguments:     args,
        expression:    null,
        typeArguments: []
      };
    }
    / DOT gen:NonWildcardTypeArguments? id:Identifier args:Arguments?
    {
      return args === null ? {
        node: 'SuperFieldAccess',
        name:  id
      } : {
        node:         'SuperMethodInvocation',
        typeArguments: optionalList(gen),
        name:          id,
        arguments:     args
      };
    }

BasicType
    = type:(
        "byte"
      / "short"
      / "char"
      / "int"
      / "long"
      / "float"
      / "double"
      / "boolean"
      ) !LetterOrDigit Spacing
    { return makePrimitive(type); }

PrimitiveType
    = BasicType

Arguments
    = EmptyLines LPAR EmptyLines args:(first:Expression rest:(COMMA EmptyLines Expression)* { return buildList(first, rest, 2); })? EmptyLines RPAR
    { return optionalList(args); }

Creator
    = type:(BasicType / CreatedName) rest:ArrayCreatorRest
    {
      return  {
        node:       'ArrayCreation',
        type:        buildArrayTree(type, rest.extraDims),
        initializer: rest.init,
        dimensions:  rest.dimms
      };
    }
    / type:CreatedName init:ArrayInitializer
    {
      return  {
        node:       'ArrayCreation',
        type:        buildArrayTree(type, []),
        initializer: init,
        dimensions:  []
      };
    }
    / args:(NonWildcardTypeArguments / EmptyWildcardTypeArguments)? type:CreatedName rest:ClassCreatorRest
    {
      return mergeProps(rest, {
        node:          'ClassInstanceCreation',
        type:           type,
        typeArguments:  args,
        expression:     null
      });
    }

CreatedName
    = qual:QualifiedIdentifier args:TypeArgumentsOrDiamond? rest:( DOT Identifier TypeArgumentsOrDiamond? )*
    { return buildTypeName(qual, args, rest); }

InnerCreator
    = id:Identifier args:NonWildcardTypeArgumentsOrDiamond? rest:ClassCreatorRest
    {
      return mergeProps(rest, {
        node: 'ClassInstanceCreation',
        type:  buildTypeName(id, args, [])
      });
    }

ClassCreatorRest
    = args:Arguments body:ClassBody?
    {
      return {
        arguments:                 args,
        anonymousClassDeclaration: body === null ? null : {
          node:            'AnonymousClassDeclaration',
          bodyDeclarations: body
        }
      };
    }

ArrayCreatorRest
    = dims:Dim+ init:ArrayInitializer
    { return { extraDims:dims, init:init, dimms: [] }; }
    / dimexpr:DimExpr+ dims:Dim*
    { return { extraDims:dimexpr.concat(dims), init:null, dimms: dimexpr }; }
    / dim:Dim
    { return { extraDims:[dim], init:null, dimms: [] }; }

ArrayElementValuePair
    = Indent name:VariableInitializer (ARROW / COLON)? value:ElementValue?
    {
        if(value) {
            return {
                node: 'ArrayMemberValuePair',
                name:  name,
                value: value
            };
        }
        else {
            return name;
        }
    }

ArrayInitializer
    = EmptyLines LWING
      init:(
        first:ArrayElementValuePair rest:(COMMA ArrayElementValuePair)*
        { return buildList(first, rest, 1); }
      )?
      COMMA? EmptyLines  RWING
    { return { node: 'ArrayInitializer', expressions: optionalList(init) }; }

VariableInitializer
    = ArrayInitializer
    / Expression

ParExpression
    = LPAR EmptyLines expr:Expression EmptyLines RPAR
    { return { node: 'ParenthesizedExpression', expression: expr }; }

QualifiedIdentifier
    = first:Identifier rest:(DOT Identifier)*
    { return buildQualified(first, rest, 1); }

Dim
    = LBRK RBRK

DimExpr
    = LBRK exp:Expression RBRK
    { return exp; }

//-------------------------------------------------------------------------
//  Types and Modifiers
//-------------------------------------------------------------------------

Type
    = type:(BasicType / ClassType) dims:Dim*
      { return buildArrayTree(type, dims); }

ReferenceType
    = bas:BasicType dims:Dim+
    { return buildArrayTree(bas, dims); }
    / cls:ClassType dims:Dim*
    { return buildArrayTree(cls, dims); }

ClassType
    = qual:QualifiedIdentifier args:TypeArguments? rest:(DOT Identifier TypeArguments?)*
    { return buildTypeName(qual, args, rest); }

ClassTypeList
    = first:ClassType rest:(COMMA ClassType)*
    { return buildList(first, rest, 1); }

TypeArguments
    = LPOINT first:TypeArgument rest:(COMMA TypeArgument)* EmptyLines RPOINT
    { return buildList(first, rest, 1); }

TypeArgument
    = EmptyLines refType:ReferenceType
    { return refType; }

TypeParameters
    = LPOINT first:TypeParameter rest:(COMMA TypeParameter)* EmptyLines RPOINT
    { return buildList(first, rest, 1); }

TypeParameter
    = EmptyLines id:Identifier
    {
      return {
        node:      'TypeParameter',
        name:       id,
      };
    }
    / EmptyLines QUERY { return { node: 'WildcardType' }; }

Modifier
    = Annotation
      / Indent keyword:(
          "public"
        / "global"
        / "protected"
        / "private"
        / "final"
        / "static"
        / "abstract"
        / "virtual"
        / "override"
        / "transient"
        / "with sharing"
        / "without sharing"
        / "testmethod"
        / "testMethod"
        / "TestMethod"
        ) !LetterOrDigit Spacing
      { return makeModifier(keyword); }

//-------------------------------------------------------------------------
//  Annotations
//-------------------------------------------------------------------------

AnnotationTypeDeclaration
    = AT INTERFACE id:Identifier body:AnnotationTypeBody
    {
      return {
        node:            'AnnotationTypeDeclaration',
        name:             id,
        bodyDeclarations: body
      };
    }

AnnotationTypeBody
    = LWING decl:AnnotationTypeElementDeclaration* RWING
    { return skipNulls(decl); }

AnnotationTypeElementDeclaration
    = modifiers:Modifier* rest:AnnotationTypeElementRest EmptyLines
    { return mergeProps(rest, { modifiers: modifiers }); }
    / SEMI
    { return null; }

AnnotationTypeElementRest
    = type:Type rest:AnnotationMethodOrConstantRest SEMI
    { return mergeProps(rest, { type: type }); }
    / ClassDeclaration
    / EnumDeclaration
    / InterfaceDeclaration
    / AnnotationTypeDeclaration

AnnotationMethodOrConstantRest
    = AnnotationMethodRest
    / AnnotationConstantRest

AnnotationMethodRest
    = id:Identifier LPAR RPAR def:DefaultValue?
    {
      return {
        node:   'AnnotationTypeMemberDeclaration',
        name:    id,
        default: def
      };
    }

AnnotationConstantRest
    = fragments:VariableDeclarators
    { return { node: 'FieldDeclaration', fragments: fragments }; }

DefaultValue
    = DEFAULT val:ElementValue
    { return val; }

Annotation
    = NormalAnnotation
    / SingleElementAnnotation
    / MarkerAnnotation

NormalAnnotation
    = Indent AT id:QualifiedIdentifier LPAR pairs:ElementValuePairs? Indent RPAR Spacing
    {
      return {
        node:    'Annotation',
        typeName: id,
        values:   optionalList(pairs)
      };
    }

SingleElementAnnotation
    = Indent AT id:QualifiedIdentifier LPAR value:ElementValue RPAR Spacing
    {
      return {
        node:    'Annotation',
        typeName: id,
        value:    value
      };
    }

MarkerAnnotation
    = Indent AT id:QualifiedIdentifier Spacing
    { return { node: 'Annotation', typeName: id }; }

ElementValuePairs
    = first:ElementValuePair rest:(COMMA ElementValuePair)*
    { return buildList(first, rest, 1); }

ElementValuePair
    = Indent name:Identifier EQU value:ElementValue
    {
      return {
        node: 'MemberValuePair',
        name:  name,
        value: value
      };
    }

ElementValue
    = ConditionalExpression
    / Annotation
    / ElementValueArrayInitializer

ElementValueArrayInitializer
    = LWING values:ElementValues? COMMA? RWING
    { return { node: 'ArrayInitializer', expressions: optionalList(values)}; }

ElementValues
    = first:ElementValue rest:(COMMA ElementValue)*
    { return buildList(first, rest, 1); }

//-------------------------------------------------------------------------
//  Spacing
//-------------------------------------------------------------------------

Indent
    = [ \t]*

Spacing
    = Indent WhiteSpaces?

WhiteSpaces
    = [\r\n\u000C]

EmptyLines
    = [ \t\r\n\u000C]*

LeadingComments
    = commentStatements:CommentStatement*
    { return leadingComments(commentStatements); }

CommentStatement
    = commentStatement:(
      comment:JavaDocComment [\r\n\u000C]*
      { return comment; }
      / comment:TraditionalComment [\r\n\u000C]*
      { return comment; }
      / comment:EndOfLineComment [\r\n\u000C]*
      { return comment; }
      )
    { return commentStatement; }

NonJavaDocComment
    = nonJavaDocComment:(
      comment:TraditionalComment [\r\n\u000C]*
      { return comment; }
      / comment:EndOfLineComment [\r\n\u000C]*
      { return comment; }
      )
    { return nonJavaDocComment; }

JavaDocComment
    = "/**" comment:MultilineCommentLetter* "*/" [\r\n\u000C]?
    { return { value: "/**" + comment.join("") + "*/" }; }

TraditionalComment
    = "/*" !("*"!"/") comment:MultilineCommentLetter* "*/" [\r\n\u000C]?
    { return { value: "/*" + comment.join("") + "*/" }; }

MultilineCommentLetter = letter:(!"*/" _)
    { return letter[1]; }

EndOfLineComment
    = "//" comment:CommentLetter* [\r\n\u000C]
    { return { value: "//" + comment.join("") }; }

CommentLetter
    = letter:(![\r\n\u000C] _)
    { return letter[1]; }

//-------------------------------------------------------------------------
//  Identifiers
//-------------------------------------------------------------------------

Identifier
    = !Keyword first:Letter rest:$LetterOrDigit* Spacing
    { return { identifier: first + rest, node: 'SimpleName' }; }

Letter = [a-z] / [A-Z] / [_$] ;

LetterOrDigit "letter or digit" = [a-z] / [A-Z] / [0-9] / [_$] ;

//-------------------------------------------------------------------------
//  Keywords
//-------------------------------------------------------------------------

Keyword
    = ( "abstract"
      / "break"
      / "case"
      / "catch"
      / "class"
      / "Class"
      / "continue"
      / "default"
      / "do"
      / "else"
      / "enum"
      / "Enum"
      / "extends"
      / "false"
      / "final"
      / "finally"
      / "for"
      / "global"
      / "if"
      / "implements"
      / "instanceof"
      / "instanceOf"
      / "interface"
      / "null"
      / "override"
      / "private"
      / "protected"
      / "public"
      / "return"
      / "static"
      / "super"
      / "switch"
      / "this"
      / "throw"
      / "transient"
      / "true"
      / "try"
      / "virtual"
      / "void"
      / "Void"
      / "while"
      ) !LetterOrDigit

AS           = Indent "as"           !LetterOrDigit Spacing
BREAK        = Indent "break"        !LetterOrDigit Spacing
CASE         = Indent "case"         !LetterOrDigit Spacing
CATCH        = Indent "catch"        !LetterOrDigit Spacing
CLASS        = Indent "class"        !LetterOrDigit Spacing
             / Indent "Class"        !LetterOrDigit Spacing
CONTINUE     = Indent "continue"     !LetterOrDigit Spacing
DEFAULT      = Indent "default"      !LetterOrDigit Spacing
DO           = Indent "do"           !LetterOrDigit Spacing
ELSE         = Indent "else"         !LetterOrDigit Spacing
ENUM         = Indent "enum"         !LetterOrDigit Spacing
             / Indent "Enum"         !LetterOrDigit Spacing
EXTENDS      = Indent "extends"      !LetterOrDigit Spacing
FINALLY      = Indent "finally"      !LetterOrDigit Spacing
FINAL        = Indent "final"        !LetterOrDigit Spacing
FOR          = Indent "for"          !LetterOrDigit Spacing
IF           = Indent "if"           !LetterOrDigit Spacing
IMPLEMENTS   = Indent "implements"   !LetterOrDigit Spacing
IMPORT       = Indent "import"       !LetterOrDigit Spacing
INTERFACE    = Indent "interface"    !LetterOrDigit Spacing
INSTANCEOF   = Indent "instanceof"   !LetterOrDigit Spacing
             / Indent "instanceOf"   !LetterOrDigit Spacing
NEW          = Indent "new"          !LetterOrDigit Spacing
             / Indent "New"          !LetterOrDigit Spacing
PACKAGE      = Indent "package"      !LetterOrDigit Spacing
RETURN       = Indent "return"       !LetterOrDigit Spacing
STATIC       = Indent "static"       !LetterOrDigit Spacing
SUPER        = Indent "super"        !LetterOrDigit Spacing
SWITCH       = Indent "switch"       !LetterOrDigit Spacing
THIS         = Indent "this"         !LetterOrDigit Spacing
THROW        = Indent "throw"        !LetterOrDigit Spacing
TRY          = Indent "try"          !LetterOrDigit Spacing
VOID         = Indent "void"         !LetterOrDigit Spacing
             / Indent "Void"         !LetterOrDigit Spacing
WHILE        = Indent "while"        !LetterOrDigit Spacing
SET          = Indent "set"          !LetterOrDigit Spacing
GET          = Indent "get"          !LetterOrDigit Spacing
INSERT       = Indent "insert"       !LetterOrDigit Spacing
UPDATE       = Indent "update"       !LetterOrDigit Spacing
UPSERT       = Indent "upsert"       !LetterOrDigit Spacing
DELETE       = Indent "delete"       !LetterOrDigit Spacing
UNDELETE     = Indent "undelete"     !LetterOrDigit Spacing
MERGE        = Indent "merge"        !LetterOrDigit Spacing

//-------------------------------------------------------------------------
//  Literals
//-------------------------------------------------------------------------

Literal
    = EmptyLines literal:( FloatLiteral
      / IntegerLiteral          // May be a prefix of FloatLiteral
      / StringLiteral
      / TemplateStringLiteral
      / TaggedStringLiteral
      / "true"  !LetterOrDigit
      { return { node: 'BooleanLiteral', booleanValue: true }; }
      / "false" !LetterOrDigit
      { return { node: 'BooleanLiteral', booleanValue: false }; }
      / "null"  !LetterOrDigit
      { return { node: 'NullLiteral' }; }
      ) Spacing
    { return literal; }

IntegerLiteral
    = DecimalNumeral [lL]?
    { return { node: 'NumberLiteral', token: text() }; }

DecimalNumeral
    = "0"
    / [0-9]([_]*[0-9])*

HexNumeral
    = ("0x" / "0X") HexDigits

BinaryNumeral
    = ("0b" / "0B") [01]([_]*[01])*

OctalNumeral
    = "0" ([_]*[0-7])+

FloatLiteral
    = DecimalFloat ![lL]
    { return { node: 'NumberLiteral', token: text() }; }

DecimalFloat
    = Digits "." Digits?  Exponent? [fFdD]?
    / "." Digits Exponent? [fFdD]?
    / Digits Exponent [fFdD]?
    / Digits Exponent? [fFdD]
    / Digits

Exponent
    = [eE] [+\-]? Digits

HexFloat
    = HexSignificand BinaryExponent [fFdD]?

HexSignificand
    = ("0x" / "0X") HexDigits? "." HexDigits
    / HexNumeral "."?                           // May be a prefix of above

BinaryExponent
    = [pP] [+\-]? Digits

Digits
    = [0-9]([_]*[0-9])*

HexDigits
    = HexDigit ([_]*HexDigit)*

HexDigit
    = [a-f] / [A-F] / [0-9]

StringLiteral
    = "\"" (Escape / !["\\\n\r] _)* "\""                   // this " keeps the editor happy
    { return { node: 'StringLiteral', escapedValue: text() }; }
    / "\'" (Escape / !['\\\n\r] _)* "\'"                   // this " keeps the editor happy
    { return { node: 'StringLiteral', escapedValue: text() }; }

TemplateStringLiteral
    = "\`" (![`] _)* "\`"                   // this " keeps the editor happy
    { return { node: 'TemplateStringLiteral', escapedValue: text() }; }

TaggedStringLiteral
    = Identifier "\`" (![`] _)* "\`"                   // this " keeps the editor happy
    { return { node: 'TaggedStringLiteral', escapedValue: text() }; }

Escape
    = "\\" ([btnfr"'\\] / OctalEscape / UnicodeEscape)     // this " keeps the editor happy

OctalEscape
    = [0-3][0-7][0-7]
    / [0-7][0-7]
    / [0-7]

UnicodeEscape
    = "u"+ HexDigit HexDigit HexDigit HexDigit

//-------------------------------------------------------------------------
//  Separators, Operators
//-------------------------------------------------------------------------

BINARY_OPERATOR =            Identifier Spacing
ARROW           =            "=>"      Spacing
AT              =            "@"       Spacing
AND             =            "&"![=&]  Spacing
ANDAND          =            "&&"      Spacing
ANDEQU          =            "&="      Spacing
BANG            =            "!" !"="  Spacing
BSR             =            ">>>"!"=" Spacing
BSREQU          =            ">>>="    Spacing
COLON           =            ":" !":"  Spacing
COLONCOLON      =            "::"      Spacing
COMMA           =            ","       Spacing
DEC             =            "--"      Spacing
DIV             =            "/" !"="  Spacing
DIVEQU          =            "/="      Spacing
DOT             = EmptyLines "."       Spacing
ELLIPSIS        =            "..."     Spacing
EQU             =            "="![=>]  Spacing
EQUAL           =            "=="![=]  Spacing
                /            "==="     Spacing
GE              =            ">="      Spacing
GT              =            ">"![=>]  Spacing
HAT             =            "^"!"="   Spacing
HATEQU          =            "^="      Spacing
INC             =            "++"      Spacing
LBRK            =            "["       Spacing
LE              =            "<="      Spacing
LPAR            =            "("       Spacing
LPOINT          =            "<"       Spacing
LT              =            "<"![=<]  Spacing
LWING           =            "{"       Spacing
MINUS           =            "-"![=\-] Spacing
MINUSEQU        =            "-="      Spacing
MOD             =            "%"!"="   Spacing
MODEQU          =            "%="      Spacing
NOTEQUAL        =            "!="![=]  Spacing
                /            "!=="     Spacing
OR              =            "|"![=|>] Spacing
OREQU           =            "|="      Spacing
OROR            =            "||"      Spacing
PIPE            =            "|>"      Spacing
PLUS            =            "+"![=+]  Spacing
PLUSEQU         =            "+="      Spacing
POINTER         =            "->"      Spacing
QUERY           =            "?"       Spacing
RBRK            =            "]"       Spacing
RPAR            =            ")"       Spacing
RPOINT          =            ">"       Spacing
RWING           =            "}"       Spacing
SEMI            =            ";"       Spacing
SL              =            "<<"!"="  Spacing
SLEQU           =            "<<="     Spacing
SR              =            ">>"![=>] Spacing
SREQU           =            ">>="     Spacing
STAR            =            "*"!"="   Spacing
STAREQU         =            "*="      Spacing
TILDA           =            "~"       Spacing

EOT = !_

_               =   .
