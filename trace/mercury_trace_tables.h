/*
** Copyright (C) 1998-1999 The University of Melbourne.
** This file may only be copied under the terms of the GNU Library General
** Public License - see the file COPYING.LIB in the Mercury distribution.
*/

/*
** This file contains the declarations of the tables that contain
** the identities of the debuggable modules and their procedures.
**
** Main author: Zoltan Somogyi.
*/

#ifndef	MERCURY_TRACE_TABLES_H
#define	MERCURY_TRACE_TABLES_H

#include	"mercury_stack_layout.h"
#include	<stdio.h>

/*
** MR_register_all_modules_and_procs gathers all available debugging info
** about the modules and procedures of the program into the module info table.
** If verbose is TRUE, print progress and summary messages.
*/

extern	void		MR_register_all_modules_and_procs(FILE *fp,
				bool verbose);

/*
** MR_register_module_layout_real registers a module layout structure.
** It is called indirectly, through the function pointer
** MR_register_module_layout, by the module initialization code
** of modules compiled with debugging.
*/

extern	void		MR_register_module_layout_real(const MR_Module_Layout
				*module);

/*
** These functions print (parts of) the module info table.
**
** MR_dump_module_tables lists all procedures in all modules.
** Its output can be very big; it should be used only by developers,
** for debugging the debugger.
**
** MR_dump_module_list lists the names of all the modules,
** while MR_dump_module_procs lists the names of all the procs in the named
** module. These are intended for ordinary, non-developer users.
*/

extern	void		MR_dump_module_tables(FILE *fp);
extern	void		MR_dump_module_list(FILE *fp);
extern	void		MR_dump_module_procs(FILE *fp, const char *name);

/*
** A procedure specification gives some or all of
**
**	the name of the module defining the procedure
**	the name of the predicate or function
**	the arity of the predicate or function
**	the mode of the predicate or function
**	whether the procedure belongs to a predicate or function
**
** A NULL pointer for the string fields, and a negative number for the other
** fields signifies the absence of information about that field, which should
** therefore be treated as a wildcard.
*/

typedef	struct {
	const char			*MR_proc_module;
	const char			*MR_proc_name;
	int				MR_proc_arity;
	int				MR_proc_mode;
	MR_PredFunc			MR_proc_pf;
} MR_Proc_Spec;

/*
** Given a string containing the specification of a procedure in the form
**
**	[`pred*'|`func*']module:name/arity-mode
**
** in which some of the five components (but not the name) may be missing,
** parse it into the more usable form of a MR_Proc_Spec. The original string
** may be overwritten in the process.
**
** Returns TRUE if the string was correctly formed, and FALSE otherwise.
*/

extern	bool	MR_parse_proc_spec(char *str, MR_Proc_Spec *spec);

/*
** Search the tables for a procedure that matches the given specification.
** If no procedure matches, return NULL.
** If one procedure matches, return its layout structure,
** and set *unique to TRUE.
** If more than one procedure matches, return the layout structure of one
** and set *unique to FALSE.
*/

extern	const MR_Stack_Layout_Entry *MR_search_for_matching_procedure(
					MR_Proc_Spec *spec, bool *unique);

/*
** MR_process_matching_procedures(spec, f, data):
**	For each procedure that matches the specification given by `spec',
**	call `f(data, entry)', where `entry' is the entry layout for that
**	procedure.  The argument `data' is a `void *' which can be used
**	to pass any other information needed by the function `f'.
*/

extern	void	MR_process_matching_procedures(MR_Proc_Spec *spec,
			void f(void *, const MR_Stack_Layout_Entry *), 
			void *data);

extern	void	MR_print_proc_id_for_debugger(FILE *fp,
			const MR_Stack_Layout_Entry *entry);

#endif	/* not MERCURY_TRACE_TABLES_H */
