/*
** Copyright (C) 1995-2000 The University of Melbourne.
** This file may only be copied under the terms of the GNU Library General
** Public License - see the file COPYING.LIB in the Mercury distribution.
*/

/* mercury_stacks.h - definitions for manipulating the det and nondet stacks */

#ifndef MERCURY_STACKS_H
#define MERCURY_STACKS_H

#include "mercury_regs.h"
#include "mercury_types.h"
#include "mercury_overflow.h"
#include "mercury_debug.h"
#include "mercury_goto.h"
#include "mercury_tabling.h"
#include "mercury_engine.h"

/*---------------------------------------------------------------------------*/

/* DEFINITIONS FOR MANIPULATING THE DET STACK */

#define	MR_based_stackvar(base_sp, n)	((base_sp)[-(n)])
#define	MR_stackvar(n)			MR_based_stackvar(MR_sp, n)

#define	MR_incr_sp_push_msg(n, msg)				\
			(					\
				MR_debugincrsp(n, MR_sp),	\
				MR_sp = MR_sp + (n),		\
				MR_detstack_overflow_check(),	\
				(void)0				\
			)

#define	MR_decr_sp_pop_msg(n)					\
			(					\
				MR_debugdecrsp(n, MR_sp),	\
				MR_sp = MR_sp - (n),		\
				MR_detstack_underflow_check(),	\
				(void)0				\
			)

#define	MR_incr_sp(n)	(					\
				MR_debugincrsp(n, MR_sp),	\
				MR_sp = MR_sp + (n),		\
				MR_detstack_overflow_check(),	\
				(void)0				\
			)

#define	MR_decr_sp(n)	(					\
				MR_debugdecrsp(n, MR_sp),	\
				MR_sp = MR_sp - (n),		\
				MR_detstack_underflow_check(),	\
				(void)0				\
			)

/*---------------------------------------------------------------------------*/

/* DEFINITIONS FOR NONDET STACK FRAMES */

#define	MR_PREVFR	(-0)	/* prev frame on stack, set up at call	*/
#define	MR_REDOIP	(-1)	/* in this proc, set up at clause entry	*/
#define	MR_REDOFR	(-2)	/* value for curfr on backtracking      */
#define	MR_SUCCIP	(-3)	/* in caller proc, set up at call	*/
#define	MR_SUCCFR	(-4)	/* frame of caller proc, set up at call	*/
#define	MR_DETFR	(-3)	/* sp, in model_det temp frames only	*/

/*
** MR_Code that traverses the nondet stack depends on the relationship
** MR_NONDET_TEMP_SIZE < MR_DET_TEMP_SIZE < MR_NONDET_FIXED_SIZE.
** All three sizes are measured in words.
*/

#define	MR_NONDET_TEMP_SIZE	3 /* prevfr, redoip, redofr */
#define	MR_DET_TEMP_SIZE	4 /* prevfr, redoip, redofr, detfr */
#define	MR_NONDET_FIXED_SIZE	5 /* prevfr, redoip, redofr, succip, succfr */

#define	MR_SAVEVAL		(-MR_NONDET_FIXED_SIZE)
				/* saved values start at this offset	*/

#define	MR_prevfr_addr(fr)	(&((MR_Word *) (fr))[MR_PREVFR])
#define	MR_redoip_addr(fr)	(&((MR_Word *) (fr))[MR_REDOIP])
#define	MR_redofr_addr(fr)	(&((MR_Word *) (fr))[MR_REDOFR])
#define	MR_succip_addr(fr)	(&((MR_Word *) (fr))[MR_SUCCIP])
#define	MR_succfr_addr(fr)	(&((MR_Word *) (fr))[MR_SUCCFR])
#define	MR_detfr_addr(fr)	(&((MR_Word *) (fr))[MR_DETFR])
#define	MR_based_framevar_addr(fr, n) \
				(&(((MR_Word *) (fr))[MR_SAVEVAL + 1 - (n)]))

#define	MR_prevfr_slot(fr)	MR_LVALUE_CAST(MR_Word *,		\
					((MR_Word *) (fr))[MR_PREVFR])
#define	MR_redoip_slot(fr)	MR_LVALUE_CAST(MR_Code *,		\
					((MR_Word *) (fr))[MR_REDOIP])
#define	MR_redofr_slot(fr)	MR_LVALUE_CAST(MR_Word *,		\
					((MR_Word *) (fr))[MR_REDOFR])
#define	MR_succip_slot(fr)	MR_LVALUE_CAST(MR_Code *,		\
					((MR_Word *) (fr))[MR_SUCCIP])
#define	MR_succfr_slot(fr)	MR_LVALUE_CAST(MR_Word *,		\
					((MR_Word *) (fr))[MR_SUCCFR])
#define	MR_detfr_slot(fr)	MR_LVALUE_CAST(MR_Word *,		\
					((MR_Word *) (fr))[MR_DETFR])
#define	MR_based_framevar(fr, n) (((MR_Word *) (fr))[MR_SAVEVAL + 1 - (n)])

#define	MR_framevar(n)		MR_based_framevar(MR_curfr, n)

/*---------------------------------------------------------------------------*/

/* DEFINITIONS FOR MANIPULATING THE NONDET STACK */

#define	MR_mkframe(predname, numslots, redoip)				\
			do {						\
				reg	MR_Word	*prevfr;		\
				reg	MR_Word	*succfr;		\
									\
				prevfr = MR_maxfr;			\
				succfr = MR_curfr;			\
				MR_maxfr += (MR_NONDET_FIXED_SIZE + numslots);\
				MR_curfr = MR_maxfr;			\
				MR_redoip_slot(MR_curfr) = redoip;	\
				MR_prevfr_slot(MR_curfr) = prevfr;	\
				MR_succip_slot(MR_curfr) = MR_succip;	\
				MR_succfr_slot(MR_curfr) = succfr;	\
				MR_redofr_slot(MR_curfr) = MR_curfr;	\
				MR_debugmkframe(predname);		\
				MR_nondstack_overflow_check();		\
			} while (0)

/* convert a size in bytes to a size in words, rounding up if necessary */
#define MR_bytes_to_words(x) (((x) + sizeof(MR_Word) - 1) / sizeof(MR_Word))

/* just like mkframe, but also reserves space for a struct     */
/* with the given tag at the bottom of the nondet stack frame  */
#define	MR_mkpragmaframe(predname, numslots, structname, redoip)	\
	do {								\
		reg	MR_Word	*prevfr;				\
		reg	MR_Word	*succfr;				\
									\
		prevfr = MR_maxfr;					\
		succfr = MR_curfr;					\
		MR_maxfr += MR_NONDET_FIXED_SIZE + numslots + 		\
			MR_bytes_to_words(sizeof(struct structname));	\
		MR_curfr = MR_maxfr;					\
		MR_redoip_slot(MR_curfr) = redoip;			\
		MR_prevfr_slot(MR_curfr) = prevfr;			\
		MR_succip_slot(MR_curfr) = MR_succip;			\
		MR_succfr_slot(MR_curfr) = succfr;			\
		MR_redofr_slot(MR_curfr) = MR_curfr;			\
		MR_debugmkframe(predname);				\
		MR_nondstack_overflow_check();				\
	} while (0)

#define	MR_mktempframe(redoip)						\
			do {						\
				reg	MR_Word	*prevfr;		\
				reg	MR_Word	*succfr;		\
									\
				prevfr = MR_maxfr;			\
				succfr = MR_curfr;			\
				MR_maxfr += MR_NONDET_TEMP_SIZE;	\
				MR_prevfr_slot(MR_maxfr) = prevfr;	\
				MR_redoip_slot(MR_maxfr) = redoip;	\
				MR_redofr_slot(MR_maxfr) = MR_curfr;	\
				MR_nondstack_overflow_check();		\
			} while (0)

#define	MR_mkdettempframe(redoip)					\
			do {						\
				reg	MR_Word	*prevfr;		\
				reg	MR_Word	*succfr;		\
									\
				prevfr = MR_maxfr;			\
				succfr = MR_curfr;			\
				MR_maxfr += MR_DET_TEMP_SIZE;		\
				MR_prevfr_slot(MR_maxfr) = prevfr;	\
				MR_redoip_slot(MR_maxfr) = redoip;	\
				MR_redofr_slot(MR_maxfr) = MR_curfr;	\
				MR_detfr_slot(MR_maxfr)  = MR_sp;	\
				MR_nondstack_overflow_check();		\
			} while (0)

#define	MR_succeed()	do {						\
				reg	MR_Word	*childfr;		\
									\
				MR_debugsucceed();			\
				childfr = MR_curfr;			\
				MR_curfr = MR_succfr_slot(childfr);	\
				MR_GOTO(MR_succip_slot(childfr));	\
			} while (0)

#define	MR_succeed_discard()						\
			do {						\
				reg	MR_Word	*childfr;		\
									\
				MR_debugsucceeddiscard();		\
				childfr = MR_curfr;			\
				MR_maxfr = MR_prevfr_slot(childfr);	\
				MR_curfr = MR_succfr_slot(childfr);	\
				MR_GOTO(MR_succip_slot(childfr));	\
			} while (0)


#define	MR_fail()	do {						\
				MR_debugfail();				\
				MR_maxfr = MR_prevfr_slot(MR_maxfr);	\
				MR_nondstack_underflow_check();		\
				MR_curfr = MR_redofr_slot(MR_maxfr);	\
				MR_GOTO(MR_redoip_slot(MR_maxfr));	\
			} while (0)


#define	MR_redo()	do {						\
				MR_debugredo();				\
				MR_curfr = MR_redofr_slot(MR_maxfr);	\
				MR_GOTO(MR_redoip_slot(MR_maxfr));	\
			} while (0)

/*---------------------------------------------------------------------------*/

/* DEFINITIONS FOR EXCEPTION HANDLING */

#ifdef CONSERVATIVE_GC
  #define MR_IF_NOT_CONSERVATIVE_GC(x)
#else
  #define MR_IF_NOT_CONSERVATIVE_GC(x) x
#endif

#ifdef MR_USE_TRAIL
  #define MR_IF_USE_TRAIL(x) x
#else
  #define MR_IF_USE_TRAIL(x)
#endif

/*
** This enum specifies the kind of handler in an exception handler
** nondet stack frame.
*/
enum MR_HandlerCodeModel {
	/* 
	** For these three values, the exception handler is a Mercury closure
	** with the specified determinism.  If an exception occurs, then
	** after the Mercury stacks have been unwound, the closure will
	** be called.
	*/
	MR_MODEL_DET_HANDLER,
	MR_MODEL_SEMI_HANDLER,
	MR_MODEL_NON_HANDLER,
	/*
	** For this value, the exception will be handled by C code using
	** setjmp/longjmp.  If an exception occurs, then after the Mercury
	** stacks have been unwound, `MR_longjmp(MR_ENGINE(e_jmp_buf))' will
	** be called.
	*/
	MR_C_LONGJMP_HANDLER
};


/*
** Define a struct for the framevars that we use in an exception handler
** nondet stack frame.  This struct gets allocated on the nondet stack
** using MR_mkpragmaframe(), with a special redoip of
** `MR_exception_handler_do_fail'.
*/
typedef struct MR_Exception_Handler_Frame_struct {
	/*
	** The `code_model' field is used to identify what kind of
	** handler it is. It holds values of type MR_HandlerMR_CodeModel
	** (see above), but it is declared to have type `MR_Word' to ensure
	** that everything remains word-aligned.
	*/
	MR_Word code_model;

	/*
	** If code_model is MR_MODEL_*_HANDLER, then
	** the `handler' field holds the Mercury closure for the handler,
	** which will be a closure of the specified determinism.
	** If code_model is MR_C_LONGJMP, then this field is unused.
	*/
	MR_Word handler;

	/*
	** The remaining fields hold stuff that must be saved in order
	** to unwind the Mercury stacks.
	*/

	/* the det stack pointer */
	MR_Word *stack_ptr;

	/* the trail state */
	MR_IF_USE_TRAIL(
		MR_Word trail_ptr;
		MR_Word ticket_counter;
	)

	/* the heap state */
	MR_IF_NOT_CONSERVATIVE_GC(
		MR_Word *heap_ptr;
		MR_Word *solns_heap_ptr;
		MR_MemoryZone *heap_zone;
	)
} MR_Exception_Handler_Frame;

#define MR_EXCEPTION_FRAMEVARS \
    (((MR_Exception_Handler_Frame *) (MR_curfr - MR_NONDET_FIXED_SIZE + 1)) - 1)

#define MR_create_exception_handler(name,				      \
		handler_code_model, handler_closure, redoip)		      \
	do {								      \
		/*							      \
		** Create a handler on the stack with the special redoip      \
		** of `MR_exception_handler_do_fail' (we'll look for this     \
		** redoip when unwinding the nondet stack in		      \
		** builtin_throw/1), and save the stuff we will		      \
		** need if an exception is thrown.			      \
		*/							      \
		MR_mkpragmaframe((name), 0,				      \
			MR_Exception_Handler_Frame_struct,		      \
			MR_ENTRY(MR_exception_handler_do_fail));	      \
		/* record the handler's code model */			      \
		MR_EXCEPTION_FRAMEVARS->code_model = (handler_code_model);    \
		/* save the handler's closure */			      \
		MR_EXCEPTION_FRAMEVARS->handler = (handler_closure);	      \
		/* save the det stack pointer */			      \
		MR_EXCEPTION_FRAMEVARS->stack_ptr = MR_sp;		      \
		MR_IF_NOT_CONSERVATIVE_GC(				      \
			/* save the heap and solutions heap pointers */	      \
			MR_EXCEPTION_FRAMEVARS->heap_ptr = MR_hp;	      \
			MR_EXCEPTION_FRAMEVARS->solns_heap_ptr = MR_sol_hp;   \
			MR_EXCEPTION_FRAMEVARS->heap_zone = 		      \
				MR_ENGINE(heap_zone);			      \
		)							      \
		MR_IF_USE_TRAIL(					      \
			/* save the trail state */			      \
			MR_mark_ticket_stack(				      \
				MR_EXCEPTION_FRAMEVARS->ticket_counter);      \
			MR_store_ticket(MR_EXCEPTION_FRAMEVARS->trail_ptr);   \
		)							      \
									      \
		/*							      \
		** Now we need to create another frame.			      \
		** This is so that we can be sure that no-one will hijack     \
		** the redoip of the special frame we created above.	      \
		** (The compiler sometimes generates ``hijacking'' code       \
		** that saves the topmost redoip on the stack, and	      \
		** temporarily replaces it with a new redoip that will	      \
		** do some processing on failure before restoring the	      \
		** original redoip.  This would cause problems when	      \
		** doing stack unwinding in builtin_throw/1, because	      \
		** we wouldn't be able to find the special redoip.	      \
		** But code will only ever hijack the topmost frame,	      \
		** so we can avoid this by creating a second frame	      \
		** above the special frame.)				      \
		*/							      \
		MR_mktempframe(redoip);				      	      \
	} while (0)


/*---------------------------------------------------------------------------*/

#ifdef	MR_USE_MINIMAL_MODEL

/* DEFINITIONS FOR GENERATOR STACK FRAMES */

typedef struct MR_GeneratorStackFrameStruct {
	MR_Word			*generator_frame;
	MR_TrieNode		generator_table;
} MR_GeneratorStackFrame;

extern	void			MR_push_generator(MR_Word *frame_addr,
					MR_TrieNode table_addr);
extern	MR_Subgoal		*MR_top_generator_table(void);
extern	void			MR_pop_generator(void);
extern	void			MR_print_gen_stack(FILE *fp);

/* DEFINITIONS FOR CUT STACK FRAMES */

typedef struct MR_CutGeneratorListNode *MR_CutGeneratorList;
struct MR_CutGeneratorListNode {
	MR_TrieNode		generator_ptr;
	MR_CutGeneratorList	next_generator;
};

typedef struct MR_CutStackFrameStruct {
	MR_Word			*frame;
	MR_Integer		gen_next;
	MR_CutGeneratorList	generators;
} MR_CutStackFrame;

extern	void			MR_commit_mark(void);
extern	void			MR_commit_cut(void);

extern	void			MR_register_generator_ptr(MR_TrieNode);

#endif	/* MR_USE_MINIMAL_MODEL */

#endif	/* not MERCURY_STACKS_H */
