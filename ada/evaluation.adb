with Ada.Text_IO;
with Envs;
with Smart_Pointers;

package body Evaluation is

   use Types;

   procedure Add_Defs (Defs : List_Mal_Type; Env : Envs.Env_Handle) is
      D, L : List_Mal_Type;
   begin
      if Debug then
         Ada.Text_IO.Put_Line ("Add_Defs " & To_String (Defs));
      end if;
      D := Defs;
      while not Is_Null (D) loop
         L := Deref_List (Cdr (D)).all;
         Envs.Set
           (Env,
            Deref_Atom (Car (D)).Get_Atom,
            Eval (Car (L), Env));
         D := Deref_List (Cdr(L)).all;
      end loop;
   end Add_Defs;


   function Def_Fn (Args : List_Mal_Type; Env : Envs.Env_Handle)
		   return Mal_Handle is
      Name, Fn_Body, Res : Mal_Handle;
   begin
      Name := Car (Args);
      pragma Assert (Deref (Name).Sym_Type = Atom,
                     "Def_Fn: expected atom as name");
      Fn_Body := Car (Deref_List (Cdr (Args)).all);
      Res := Eval (Fn_Body, Env);
      Envs.Set (Envs.Get_Current, Deref_Atom (Name).Get_Atom, Res);
      return Res;
   end Def_Fn;


   function Def_Macro (Args : List_Mal_Type; Env : Envs.Env_Handle)
		   return Mal_Handle is
      Name, Fn_Body, Res : Mal_Handle;
      Lambda_P : Lambda_Ptr;
   begin
      Name := Car (Args);
      pragma Assert (Deref (Name).Sym_Type = Atom,
                     "Def_Macro: expected atom as name");
      Fn_Body := Car (Deref_List (Cdr (Args)).all);
      Res := Eval (Fn_Body, Env);
      Lambda_P := Deref_Lambda (Res);
      Lambda_P.Set_Is_Macro (True);
      Envs.Set (Envs.Get_Current, Deref_Atom (Name).Get_Atom, Res);
      return Res;
   end Def_Macro;


   function Macro_Expand (Ast : Mal_Handle; Env : Envs.Env_Handle)
   return Mal_Handle is
      Res : Mal_Handle;
      LP : Lambda_Ptr;
      LMT : List_Mal_Type;
   begin

      Res := Ast;

      loop

         if Deref (Res).Sym_Type /= List then
            return Res;
         end if;

         LMT := Deref_List (Res).all;

         LP := Get_Macro (Res, Env);

      exit when LP = null or else not LP.Get_Is_Macro;

	  declare
	     Fn_List : Mal_Handle := Cdr (LMT);
	     Params : List_Mal_Type;
	     E : Envs.Env_Handle;
	  begin
	     E := Envs.New_Env (LP.Get_Env);
	     Params := Deref_List (LP.Get_Params).all;
	     if Envs.Bind (E, Params, Deref_List (Fn_List).all) then

	        Res := Eval (LP.Get_Expr, E); 
      
             end if;

	  end;

      end loop;

      return Res;

   end Macro_Expand;


   function Let_Processing (Args : List_Mal_Type; Env : Envs.Env_Handle)
			   return Mal_Handle is
      Defs, Expr, Res : Mal_Handle;
   begin
      Envs.New_Env;
      Defs := Car (Args);
      Add_Defs (Deref_List (Defs).all, Envs.Get_Current);
      Expr := Car (Deref_List (Cdr (Args)).all);
      Res := Eval (Expr, Envs.Get_Current);
      Envs.Delete_Env;
      return Res;
   end Let_Processing;


   function Eval_As_Boolean (MH : Mal_Handle) return Boolean is
      Res : Boolean;
   begin
      case Deref (MH).Sym_Type is
         when Bool => 
            Res := Deref_Bool (MH).Get_Bool;
         when Atom =>
            return not (Deref_Atom (MH).Get_Atom = "nil");
--         when List =>
--            declare
--               L : List_Mal_Type;
--            begin
--               L := Deref_List (MH).all;
--               Res := not Is_Null (L);
--            end;
         when others => -- Everything else
            Res := True;
      end case;
      return Res;
   end Eval_As_Boolean;


   function Eval_Ast
     (Ast : Mal_Handle; Env : Envs.Env_Handle)
     return Mal_Handle is

      function Call_Eval (A : Mal_Handle) return Mal_Handle is
      begin
         return Eval (A, Env);
      end Call_Eval;

   begin

      case Deref (Ast).Sym_Type is

         when Atom =>

            declare
               Sym : Mal_String := Deref_Atom (Ast).Get_Atom;
            begin
               -- if keyword or nil (which may represent False)...
               if Sym(1) = ':' then
                  return Ast;
               else
                  return Envs.Get (Env, Sym);
               end if;
            exception
               when Envs.Not_Found =>
                  return New_Error_Mal_Type ("'" &  Sym & "' not found");
            end;

         when List =>

            return Map (Call_Eval'Unrestricted_Access, Deref_List (Ast).all);

         when Lambda =>

            -- Evaluating a lambda in a different Env.
            declare
               L : Lambda_Ptr;
               New_Env : Envs.Env_Handle;
            begin
               L := Deref_Lambda (Ast);
               New_Env := Env;
               -- Make the current Lambda's env the outer of the env param.
               Envs.Set_Outer (New_Env, L.Get_Env);
               -- Make the Lambda's Env.
               L.Set_Env (New_Env);
               return Ast;
            end;

         when others => return Ast;

      end case;

   end Eval_Ast;


   function Do_Processing (Do_List : List_Mal_Type; Env : Envs.Env_Handle)
			  return Mal_Handle is
      D : List_Mal_Type;
      Res : Mal_Handle := Smart_Pointers.Null_Smart_Pointer;
   begin
      if Debug then
         Ada.Text_IO.Put_Line ("Do-ing " & To_String (Do_List));
      end if;
      D := Do_List;
      while not Is_Null (D) loop
         Res := Eval (Car (D), Env);
         D := Deref_List (Cdr(D)).all;
      end loop;
      return Res;
   end Do_Processing;


   function Quasi_Quote_Processing (Param : Mal_Handle) return Mal_Handle is
      Res, First_Elem, FE_0 : Mal_Handle;
      D, Ast : List_Mal_Type;
      L : List_Ptr;
   begin

      if Debug then
         Ada.Text_IO.Put_Line ("QuasiQt " & Deref (Param).To_String);
      end if;

      -- Create a New List for the result...
      Res := New_List_Mal_Type (List_List);
      L := Deref_List (Res);

      -- This is the equivalent of Is_Pair
      if Deref (Param).Sym_Type /= List or else
         Is_Null (Deref_List (Param).all) then

         -- return a new list containing: a symbol named "quote" and ast.
         L.Append (New_Atom_Mal_Type ("quote"));
         L.Append (Param);
         return Res;

      end if;

      -- Ast is a non-empty list at this point.

      Ast := Deref_List (Param).all;

      First_Elem := Car (Ast);

      -- if the first element of ast is a symbol named "unquote":
      if Deref (First_Elem).Sym_Type = Atom and then
         Deref_Atom (First_Elem).Get_Atom = "unquote" then

         -- return the second element of ast.`
         D := Deref_List (Cdr (Ast)).all;
         return Car (D);

      end if;

      -- if the first element of first element of `ast` (`ast[0][0]`)
      -- is a symbol named "splice-unquote"
      if Deref (First_Elem).Sym_Type = List and then
         not Is_Null (Deref_List (First_Elem).all) then

         D := Deref_List (First_Elem).all;
         FE_0 := Car (D);

         if Deref (FE_0).Sym_Type = Atom and then
            Deref_Atom (FE_0).Get_Atom = "splice-unquote" then

            -- return a new list containing: a symbol named "concat",
            L.Append (New_Atom_Mal_Type ("concat"));

            -- the second element of first element of ast (ast[0][1]),
            D := Deref_List (Cdr (D)).all;
            L.Append (Car (D));

            -- and the result of calling quasiquote with
            -- the second through last element of ast.
            L.Append (Quasi_Quote_Processing (Cdr (Ast)));

            return Res;

         end if;

      end if;

      -- otherwise: return a new list containing: a symbol named "cons",
      L.Append (New_Atom_Mal_Type ("cons"));

      -- the result of calling quasiquote on first element of ast (ast[0]),
      L.Append (Quasi_Quote_Processing (Car (Ast)));

      -- and result of calling quasiquote with the second through last element of ast.
      L.Append (Quasi_Quote_Processing (Cdr (Ast)));

      return Res;

   end Quasi_Quote_Processing;


   function Eval (AParam : Mal_Handle; AnEnv : Envs.Env_Handle)
		 return Mal_Handle is
      Param : Mal_Handle;
      Env : Envs.Env_Handle;
      First_Elem : Mal_Handle;
   begin

      Param := AParam;
      Env := AnEnv;

  <<Tail_Call_Opt>>

      if Debug then
         Ada.Text_IO.Put_Line ("Evaling " & Deref (Param).To_String);
      end if;

      Param := Macro_Expand (Param, Env);

      if Debug then
         Ada.Text_IO.Put_Line ("After expansion " & Deref (Param).To_String);
      end if;

      if Deref (Param).Sym_Type = List and then
	Deref_List (Param).all.Get_List_Type = List_List then

	 declare
	    L : Mal_Handle := Param;
	    LMT, Rest_List : List_Mal_Type;
	    First_Elem, Rest_Handle : Mal_Handle;
	 begin

	    LMT := Deref_List (L).all;

	    First_Elem := Car (LMT);

	    Rest_Handle := Cdr (LMT);

	    Rest_List := Deref_List (Rest_Handle).all;

	    case Deref (First_Elem).Sym_Type is

	       when Int | Floating | Bool | Str =>
		  
		  return First_Elem;

	       when Atom =>

		  declare
		     Atom_P : Atom_Ptr;
		  begin
		     Atom_P := Deref_Atom (First_Elem);
		     if Atom_P.Get_Atom = "def!" then
			return Def_Fn (Rest_List, Env);
		     elsif Atom_P.Get_Atom = "defmacro!" then
			return Def_Macro (Rest_List, Env);
		     elsif Atom_P.Get_Atom = "macroexpand" then
			return Macro_Expand (Rest_Handle, Env);
		     elsif Atom_P.Get_Atom = "let*" then
			return Let_Processing (Rest_List, Env);
		     elsif Atom_P.Get_Atom = "do" then
			return Do_Processing (Rest_List, Env);
		     elsif Atom_P.Get_Atom = "if" then
			declare
			   Args : List_Mal_Type := Rest_List;

			   Cond, True_Part, False_Part : Mal_Handle;
			   Cond_Bool : Boolean;
			   pragma Assert (Length (Args) = 2 or Length (Args) = 3,
					  "If_Processing: not 2 or 3 parameters");
			   L : List_Mal_Type;
			begin
			   
			   Cond := Eval (Car (Args), Env);

			   Cond_Bool := Eval_As_Boolean (Cond);

			   if Cond_Bool then
			      L := Deref_List (Cdr (Args)).all;

			      Param := Car (L);
			      goto Tail_Call_Opt;
			      -- was: return Eval (Car (L), Env);
			   else
			      if Length (Args) = 3 then
				 L := Deref_List (Cdr (Args)).all;
				 L := Deref_List (Cdr (L)).all;

				 Param := Car (L);
				 goto Tail_Call_Opt;
				 -- was: return Eval (Car (L), Env);
			      else
				 return New_Atom_Mal_Type ("nil");
			      end if;
			   end if;
			end;

		     elsif Atom_P.Get_Atom = "quote" then
                        return Car (Rest_List);
		     elsif Atom_P.Get_Atom = "quasiquote" then
		        Param := Quasi_Quote_Processing (Car (Rest_List));
		        goto Tail_Call_Opt;
		     else -- not a special form

			-- Apply section
			declare
			   Res : Mal_Handle;
			begin
			   -- Eval the atom.
			   Res := Eval_Ast (L, Env);
			   Param := Res;
			   goto Tail_Call_Opt;
			   -- was: return Eval (Res, Env);
			end;

		     end if;
		  end;

	       when Func =>

		  return Call_Func
		    (Deref_Func (First_Elem).all,
		     Rest_Handle,
		     Env);

	       when Lambda =>

		  declare
		     LP : Lambda_Ptr := Deref_Lambda (First_Elem);
		     Fn_List : Mal_Handle := Cdr (LMT);
		     Params : List_Mal_Type;
		     E : Envs.Env_Handle;
		  begin
		     E := Envs.New_Env (LP.Get_Env);
		     Params := Deref_List (LP.Get_Params).all;
		     if Envs.Bind (E, Params, Deref_List (Fn_List).all) then

		        Param := LP.Get_Expr;
		        Env := E;
		        goto Tail_Call_Opt;
		        -- was: return Eval (LP.Get_Expr, E); 
       
                     else
                        return First_Elem;
                     end if;

		  end;

	       when List => 

		  -- First elem in the list is a list.
		  -- Eval it and then insert it as first elem in the list and
		  -- go again.
		  declare
		     Evaled_List : Mal_Handle;
		     E : Envs.Env_Handle;
		  begin
		     Evaled_List := Eval (First_Elem, Env);
		     if Is_Null (Evaled_List) then
			return Evaled_List;
		     elsif Deref (Evaled_List).Sym_Type = Lambda then
			E := Deref_Lambda (Evaled_List).Get_Env;
		     else
			E := Env;
		     end if;

		     Param := Prepend (Evaled_List, Rest_List);
		     Env := E;
		     goto Tail_Call_Opt;
                     -- was:
		     -- Evaled_List := Prepend (Evaled_List, Rest_List);
		     -- return Eval (Evaled_List, E);
		  end;

	       when Error => return First_Elem;

	       when Node => return New_Error_Mal_Type ("Evaluating a node");

	       when Unitary => null; -- Not yet impl

	    end case;

	 end;

      elsif Deref (Param).Sym_Type = Unitary then
         declare
            UMT : Types.Unitary_Mal_Type;
         begin
            UMT := Deref_Unitary (Param).all;
            case UMT.Get_Func is
               when Quote =>
                  return UMT.Get_Op;
               when QuasiQuote =>
		  Param := Quasi_Quote_Processing (UMT.Get_Op);
                  goto Tail_Call_Opt;
               when Unquote =>
		  Param := UMT.Get_Op;
                  goto Tail_Call_Opt;
               when others => null;
            end case;
         end;
      else

         return Eval_Ast (Param, Env);

      end if;

   end Eval;


end Evaluation;
