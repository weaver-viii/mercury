/*
** Copyright (C) 1995-2000 The University of Melbourne.
** This file may only be copied under the terms of the GNU Library General
** Public License - see the file COPYING.LIB in the Mercury distribution.
*/

/*
** mercury_type_info.h -
**	Definitions for accessing the type_infos, type_layouts, and
**	type_functors tables generated by the Mercury compiler.
**	Also contains definitions for accessing the Mercury `univ' type.
**
**	Changes here may also require changes in:
**
**		compiler/base_type_info.m
**		compiler/base_type_layout.m
**		compiler/polymorphism.m
**		compiler/higher_order.m 
**			(for updating the compiler-generated RTTI
**			structures)
**
**		library/array.m
**		library/builtin.m
**		library/private_builtin.m
**		library/std_util.m
**		runtime/mercury_bootstrap.c
**		runtime/mercury_type_info.c
**			(for updating the hand-written RTTI
**			structures)
*/

#ifndef MERCURY_TYPE_INFO_H
#define MERCURY_TYPE_INFO_H

#include "mercury_types.h"	/* for `Word' */

/*---------------------------------------------------------------------------*/



/* 
** The version of the RTTI data structures -- useful for bootstrapping.
** MR_RTTI_VERSION sets the version number in the handwritten
** type_ctor_infos.
** If you write runtime code that checks this version number and
** can at least handle the previous version of the data
** structure, it makes it easier to bootstrap changes to the data
** structures used for RTTI.
**
** This number should be kept in sync with type_ctor_info_version in
** compiler/base_type_info.m.
*/

#define MR_RTTI_VERSION 		MR_RTTI_VERSION__USEREQ
#define MR_RTTI_VERSION__INITIAL 	2
#define MR_RTTI_VERSION__USEREQ 	3

/*
** Check that the RTTI version is in a sensible range.
** The lower bound should be the lowest currently supported version
** number.  The upper bound is the current version number.
** If you increase the lower bound you should also increase the binary
** compatibility version number in runtime/mercury_grade.h (MR_GRADE_PART_0).
*/

#define MR_TYPE_CTOR_INFO_CHECK_RTTI_VERSION_RANGE(typector)	\
	assert(MR_RTTI_VERSION__USEREQ <= typector->type_ctor_version \
		&& typector->type_ctor_version <= MR_RTTI_VERSION__USEREQ)

/*---------------------------------------------------------------------------*/

/*
** For now, we don't give a C definition of the structures of typeinfos
** and pseudotypeinfos. We may change this later.
*/

typedef	Word	MR_TypeInfo;
typedef	Word	MR_PseudoTypeInfo;

/*---------------------------------------------------------------------------*/

/*
** Define offsets of fields in the type_ctor_info or type_info structure.
** See polymorphism.m for explanation of these offsets and how the
** type_info and type_ctor_info structures are laid out.
**
** ANY CHANGES HERE MUST BE MATCHED BY CORRESPONDING CHANGES
** TO THE DOCUMENTATION IN compiler/polymorphism.m.
**
** The current type_info representation *depends* on OFFSET_FOR_COUNT being 0.
*/

#define OFFSET_FOR_COUNT 0
#define OFFSET_FOR_UNIFY_PRED 1
#define OFFSET_FOR_INDEX_PRED 2
#define OFFSET_FOR_COMPARE_PRED 3
#define OFFSET_FOR_TYPE_CTOR_REPRESENTATION 4
#define OFFSET_FOR_BASE_TYPE_FUNCTORS 5
#define OFFSET_FOR_BASE_TYPE_LAYOUT 6
#define OFFSET_FOR_TYPE_MODULE_NAME 7
#define OFFSET_FOR_TYPE_NAME 8

/*
** Define offsets of fields in the type_info structure.
*/

#define OFFSET_FOR_ARG_TYPE_INFOS 1

/*
** Where the predicate arity and args are stored in the type_info.
** They are stored in the type_info (*not* the type_ctor_info).
** This is brought about by higher-order predicates all using the
** same type_ctor_info - pred/0.
*/

#define TYPEINFO_OFFSET_FOR_PRED_ARITY 1
#define TYPEINFO_OFFSET_FOR_PRED_ARGS 2

/*---------------------------------------------------------------------------*/

/*
** Definitions for handwritten code, mostly for mercury_compare_typeinfo.
*/

#define MR_COMPARE_EQUAL 0
#define MR_COMPARE_LESS 1
#define MR_COMPARE_GREATER 2

/*---------------------------------------------------------------------------*/

/*
** Definitions and macros for type_ctor_layout definition.
**
** See compiler/base_type_layout.m for more information.
**
** If we don't have enough tags, we have to encode layouts
** less densely. The make_typelayout macro does this, and
** is intended for handwritten code. Compiler generated
** code can (and does) just create two rvals instead of one. 
**
*/

/*
** Conditionally define USE_TYPE_LAYOUT.
**
** All code using type_layout structures should check to see if
** USE_TYPE_LAYOUT is defined, and give a fatal error otherwise.
** USE_TYPE_LAYOUT can be explicitly turned off with NO_TYPE_LAYOUT.
**
*/
#if !defined(NO_TYPE_LAYOUT)
	#define USE_TYPE_LAYOUT
#else
	#undef USE_TYPE_LAYOUT
#endif


/*
** Code intended for defining type_layouts for handwritten code.
**
** See library/io.m or library/builtin.m for details.
*/
#if TAGBITS >= 2
	typedef const Word *TypeLayoutField;
	#define TYPE_LAYOUT_FIELDS \
		TypeLayoutField f1,f2,f3,f4,f5,f6,f7,f8;
	#define make_typelayout(Tag, Value) \
		MR_mkword(MR_mktag(Tag), (Value))
#else
	typedef const Word *TypeLayoutField;
	#define TYPE_LAYOUT_FIELDS \
		TypeLayoutField f1,f2,f3,f4,f5,f6,f7,f8;
		TypeLayoutField f9,f10,f11,f12,f13,f14,f15,f16;
	#define make_typelayout(Tag, Value) \
		(const Word *) (Tag), \
		(const Word *) (Value)
#endif

/*
** Declaration for structs.
*/

#define MR_DECLARE_STRUCT(T)			\
	extern const struct T##_struct T
#define MR_DECLARE_TYPE_CTOR_INFO_STRUCT(T)			\
	extern const struct MR_TypeCtorInfo_struct T

/*
** Typelayouts for builtins are often defined as X identical
** values, where X is the number of possible tag values.
*/

#if TAGBITS == 0
#define make_typelayout_for_all_tags(Tag, Value) \
	make_typelayout(Tag, Value)
#elif TAGBITS == 1
#define make_typelayout_for_all_tags(Tag, Value) \
	make_typelayout(Tag, Value), \
	make_typelayout(Tag, Value)
#elif TAGBITS == 2
#define make_typelayout_for_all_tags(Tag, Value) \
	make_typelayout(Tag, Value), \
	make_typelayout(Tag, Value), \
	make_typelayout(Tag, Value), \
	make_typelayout(Tag, Value)
#elif TAGBITS == 3
#define make_typelayout_for_all_tags(Tag, Value) \
	make_typelayout(Tag, Value), \
	make_typelayout(Tag, Value), \
	make_typelayout(Tag, Value), \
	make_typelayout(Tag, Value), \
	make_typelayout(Tag, Value), \
	make_typelayout(Tag, Value), \
	make_typelayout(Tag, Value), \
	make_typelayout(Tag, Value)
#endif

#if !defined(make_typelayout_for_all_tags)
#error "make_typelayout_for_all_tags is not defined for this number of tags"
#endif

/*---------------------------------------------------------------------------*/

/* 
** Tags in type_layout structures.
** 
** These definitions are intended for use in handwritten
** C code. 
**
** Some of the type-layout tags are shared.
*/

#define TYPE_CTOR_LAYOUT_CONST_TAG		0
#define TYPE_CTOR_LAYOUT_SHARED_LOCAL_TAG	0 
#define TYPE_CTOR_LAYOUT_UNSHARED_TAG		1
#define TYPE_CTOR_LAYOUT_SHARED_REMOTE_TAG	2
#define TYPE_CTOR_LAYOUT_EQUIV_TAG		3
#define TYPE_CTOR_LAYOUT_NO_TAG		3 

/* 
** Values in type_layout structures,
** presently the values of CONST_TAG words.
**
** Also intended for use in handwritten C code.
**
** Note that MR_TYPE_CTOR_LAYOUT_UNASSIGNED_VALUE is not yet
** used for anything.
**
** Changes in this type may need to be reflected in
** compiler/base_type_layout.m.
**
** XXX Much of the information in this type is now stored in TypeCtorRep;
** it is here only temporarily.
*/

enum MR_TypeLayoutValue {
	MR_TYPE_CTOR_LAYOUT_UNASSIGNED_VALUE,
	MR_TYPE_CTOR_LAYOUT_UNUSED_VALUE,
	MR_TYPE_CTOR_LAYOUT_STRING_VALUE,
	MR_TYPE_CTOR_LAYOUT_FLOAT_VALUE,
	MR_TYPE_CTOR_LAYOUT_INT_VALUE,
	MR_TYPE_CTOR_LAYOUT_CHARACTER_VALUE,
	MR_TYPE_CTOR_LAYOUT_UNIV_VALUE,
	MR_TYPE_CTOR_LAYOUT_PREDICATE_VALUE,
	MR_TYPE_CTOR_LAYOUT_VOID_VALUE,
	MR_TYPE_CTOR_LAYOUT_ARRAY_VALUE,
	MR_TYPE_CTOR_LAYOUT_TYPEINFO_VALUE,
	MR_TYPE_CTOR_LAYOUT_C_POINTER_VALUE,
	MR_TYPE_CTOR_LAYOUT_TYPECLASSINFO_VALUE,
		/*
		** The following enum values represent the "types" of
		** of values stored in lvals that the garbage collector
		** and/or the debugger need to know about.
		*/
	MR_TYPE_CTOR_LAYOUT_SUCCIP_VALUE,
	MR_TYPE_CTOR_LAYOUT_HP_VALUE,
	MR_TYPE_CTOR_LAYOUT_CURFR_VALUE,
	MR_TYPE_CTOR_LAYOUT_MAXFR_VALUE,
	MR_TYPE_CTOR_LAYOUT_REDOFR_VALUE,
	MR_TYPE_CTOR_LAYOUT_REDOIP_VALUE,
	MR_TYPE_CTOR_LAYOUT_TRAIL_PTR_VALUE,
	MR_TYPE_CTOR_LAYOUT_TICKET_VALUE,
	MR_TYPE_CTOR_LAYOUT_UNWANTED_VALUE
};

/* 
** Highest allowed type variable number
** (corresponds with argument number of type parameter).
**
** Should be kept in sync with the default value of MR_VARIABLE_SIZED
** in mercury_conf_params.h.
*/

#define TYPE_CTOR_LAYOUT_MAX_VARINT		1024

#define TYPEINFO_IS_VARIABLE(T)		( (Word) T <= TYPE_CTOR_LAYOUT_MAX_VARINT )

/*
** This constant is also used for other information - for
** ctor infos a small integer is used for higher order types.
** Even integers represent preds, odd represent functions.
** The arity of the pred or function can be found by dividing by
** two (integer division).
*/

#define MR_TYPE_CTOR_INFO_HO_PRED				\
	((MR_TypeCtorInfo) &mercury_data___type_ctor_info_pred_0)
#define MR_TYPE_CTOR_INFO_HO_FUNC				\
	((MR_TypeCtorInfo) &mercury_data___type_ctor_info_func_0)
#define MR_TYPE_CTOR_INFO_IS_HO_PRED(T)				\
	(T == MR_TYPE_CTOR_INFO_HO_PRED)
#define MR_TYPE_CTOR_INFO_IS_HO_FUNC(T)				\
	(T == MR_TYPE_CTOR_INFO_HO_FUNC)
#define MR_TYPE_CTOR_INFO_IS_HO(T)				\
	(T == MR_TYPE_CTOR_INFO_HO_FUNC || T == MR_TYPE_CTOR_INFO_HO_PRED)

#define MR_TYPECTOR_IS_HIGHER_ORDER(T)				\
	( (Word) T <= TYPE_CTOR_LAYOUT_MAX_VARINT )
#define MR_TYPECTOR_MAKE_PRED(Arity)				\
	( (Word) ((Integer) (Arity) * 2) )
#define MR_TYPECTOR_MAKE_FUNC(Arity)				\
	( (Word) ((Integer) (Arity) * 2 + 1) )
#define MR_TYPECTOR_GET_HOT_ARITY(T)				\
	((Integer) (T) / 2 )
#define MR_TYPECTOR_GET_HOT_NAME(T)				\
	((ConstString) ( ( ((Integer) (T)) % 2 ) ? "func" : "pred" ))
#define MR_TYPECTOR_GET_HOT_MODULE_NAME(T)				\
	((ConstString) "builtin")
#define MR_TYPECTOR_GET_HOT_TYPE_CTOR_INFO(T)			\
	((Word) ( ( ((Integer) (T)) % 2 ) ?		\
		(const Word *) &mercury_data___type_ctor_info_func_0 :	\
		(const Word *) &mercury_data___type_ctor_info_pred_0 ))

/*
** Offsets into the type_layout structure for functors and arities.
**
** Constant and enumeration values start at 0, so the functor
** is at OFFSET + const/enum value. 
** 
** Functors for unshared tags are at OFFSET + arity (the functor is
** stored after all the argument info.
**
*/

#define TYPE_CTOR_LAYOUT_CONST_FUNCTOR_OFFSET		2
#define TYPE_CTOR_LAYOUT_ENUM_FUNCTOR_OFFSET		2
#define TYPE_CTOR_LAYOUT_UNSHARED_FUNCTOR_OFFSET	1

#define TYPE_CTOR_LAYOUT_UNSHARED_ARITY_OFFSET  	0
#define TYPE_CTOR_LAYOUT_UNSHARED_ARGS_OFFSET       	1

/*---------------------------------------------------------------------------*/

/* 
** Offsets for dealing with `univ' types.
**
** `univ' is represented as a two word structure.
** The first word contains the address of a type_info for the type.
** The second word contains the data.
*/

#define UNIV_OFFSET_FOR_TYPEINFO 		0
#define UNIV_OFFSET_FOR_DATA			1

/*---------------------------------------------------------------------------*/

/*
** Code for dealing with the static code addresses stored in
** type_ctor_infos. 
*/

/*
** Definitions for initialization of type_ctor_infos. If
** MR_STATIC_CODE_ADDRESSES are not available, we need to initialize
** the special predicates in the type_ctor_infos.
*/

/*
** A fairly generic static code address initializer - at least for entry
** labels.
*/
#define MR_INIT_CODE_ADDR(Base, PredAddr, Offset)			\
	do {								\
		Declare_entry(PredAddr);				\
		((Word *) (Word) &Base)[Offset]	= (Word) ENTRY(PredAddr);\
	} while (0)
			

#define MR_SPECIAL_PRED_INIT(Base, TypeId, Offset, Pred)	\
	MR_INIT_CODE_ADDR(Base, mercury____##Pred##___##TypeId, Offset)

/*
** Macros are provided here to initialize type_ctor_infos, both for
** builtin types (such as in library/builtin.m) and user
** defined C types (like library/array.m). Also, the automatically
** generated code uses these initializers.
**
** Examples of use:
**
** MR_INIT_BUILTIN_TYPE_CTOR_INFO(
** 	mercury_data__type_ctor_info_string_0, _string_);
**
** note we use _string_ to avoid the redefinition of string via #define
**
** MR_INIT_TYPE_CTOR_INFO(
** 	mercury_data_group__type_ctor_info_group_1, group__group_1_0);
** 
** MR_INIT_TYPE_CTOR_INFO_WITH_PRED(
** 	mercury_date__type_ctor_info_void_0, mercury__unused_0_0);
**
** This will initialize a type_ctor_info with a single code address.
**
**
*/

#ifndef MR_STATIC_CODE_ADDRESSES

  #define MR_MAYBE_STATIC_CODE(X)	((Integer) 0)

  #define MR_STATIC_CODE_CONST

  #define	MR_INIT_BUILTIN_TYPE_CTOR_INFO(B, T)			\
  do {									\
	MR_INIT_CODE_ADDR(B, mercury__builtin_unify##T##2_0, 		\
		OFFSET_FOR_UNIFY_PRED);					\
	MR_INIT_CODE_ADDR(B, mercury__builtin_index##T##2_0, 		\
		OFFSET_FOR_INDEX_PRED);					\
	MR_INIT_CODE_ADDR(B, mercury__builtin_compare##T##3_0, 		\
		OFFSET_FOR_COMPARE_PRED);				\
  } while (0)

  #define	MR_INIT_TYPE_CTOR_INFO_WITH_PRED(B, P)			\
  do {									\
	MR_INIT_CODE_ADDR(B, P, OFFSET_FOR_UNIFY_PRED);			\
	MR_INIT_CODE_ADDR(B, P, OFFSET_FOR_INDEX_PRED);			\
	MR_INIT_CODE_ADDR(B, P, OFFSET_FOR_COMPARE_PRED);		\
  } while (0)

  #define	MR_INIT_TYPE_CTOR_INFO(B, T)				\
  do {									\
	MR_SPECIAL_PRED_INIT(B, T, OFFSET_FOR_UNIFY_PRED, Unify);	\
	MR_SPECIAL_PRED_INIT(B, T, OFFSET_FOR_INDEX_PRED, Index);	\
	MR_SPECIAL_PRED_INIT(B, T, OFFSET_FOR_COMPARE_PRED, Compare);	\
  } while (0)

#else	/* MR_STATIC_CODE_ADDRESSES */

  #define MR_MAYBE_STATIC_CODE(X)	(X)

  #define MR_STATIC_CODE_CONST const

  #define MR_INIT_BUILTIN_TYPE_CTOR_INFO(B, T) \
	do { } while (0)

  #define MR_INIT_TYPE_CTOR_INFO_WITH_PRED(B, P) \
	do { } while (0)

  #define MR_INIT_TYPE_CTOR_INFO(B, T) \
	do { } while (0)

#endif /* MR_STATIC_CODE_ADDRESSES */

/*---------------------------------------------------------------------------*/

/*
** Macros and defintions for defining and dealing with
** type_ctor_functors.
*/

/*
** All type_functors have an indicator.
*/

#define MR_TYPE_CTOR_FUNCTORS_OFFSET_FOR_INDICATOR	((Integer) 0)

#define MR_TYPE_CTOR_FUNCTORS_INDICATOR(Functors)				\
	((Functors)[MR_TYPE_CTOR_FUNCTORS_OFFSET_FOR_INDICATOR])


/*
** Values that the indicator can take.
*/

#define MR_TYPE_CTOR_FUNCTORS_DU	((Integer) 0)
#define MR_TYPE_CTOR_FUNCTORS_ENUM	((Integer) 1)
#define MR_TYPE_CTOR_FUNCTORS_EQUIV	((Integer) 2)
#define MR_TYPE_CTOR_FUNCTORS_SPECIAL	((Integer) 3)
#define MR_TYPE_CTOR_FUNCTORS_NO_TAG	((Integer) 4)
#define MR_TYPE_CTOR_FUNCTORS_UNIV	((Integer) 5)


	/*
	** Macros to access the data in a discriminated union
	** type_functors, the number of functors, and the functor descriptor
	** for functor number N (where N starts at 1). 
	*/

#define MR_TYPE_CTOR_FUNCTORS_DU_OFFSET_FOR_NUM_FUNCTORS	((Integer) 1)
#define MR_TYPE_CTOR_FUNCTORS_DU_OFFSET_FOR_FUNCTOR_DESCRIPTORS	((Integer) 2)

#define MR_TYPE_CTOR_FUNCTORS_DU_NUM_FUNCTORS(Functors)			\
	((Functors)[MR_TYPE_CTOR_FUNCTORS_DU_OFFSET_FOR_NUM_FUNCTORS])

#define MR_TYPE_CTOR_FUNCTORS_DU_FUNCTOR_N(Functor, N)			\
	((Word *) ((Functor)[						\
		MR_TYPE_CTOR_FUNCTORS_DU_OFFSET_FOR_FUNCTOR_DESCRIPTORS + N]))

	/*
	** Macros to access the data in a enumeration type_functors, the
	** number of functors, and the enumeration vector.
	*/

#define MR_TYPE_CTOR_FUNCTORS_ENUM_OFFSET_FOR_ENUM_VECTOR	\
		((Integer) 1)

#define MR_TYPE_CTOR_FUNCTORS_ENUM_NUM_FUNCTORS(Functors)		\
	MR_TYPE_CTOR_LAYOUT_ENUM_VECTOR_NUM_FUNCTORS(			\
		MR_TYPE_CTOR_FUNCTORS_ENUM_VECTOR((Functors)))

#define MR_TYPE_CTOR_FUNCTORS_ENUM_VECTOR(Functor)			\
	((Word *) ((Functor)						\
		[MR_TYPE_CTOR_FUNCTORS_ENUM_OFFSET_FOR_ENUM_VECTOR]))

	/*
	** Macros to access the data in a no_tag type_functors, the
	** functor descriptor for the functor (there can only be one functor
	** with no_tags).
	*/

#define MR_TYPE_CTOR_FUNCTORS_NO_TAG_OFFSET_FOR_FUNCTOR_DESCRIPTOR \
	((Integer) 1)

#define MR_TYPE_CTOR_FUNCTORS_NO_TAG_FUNCTOR(Functors)			\
	((Word *) ((Functors)						\
		[MR_TYPE_CTOR_FUNCTORS_NO_TAG_OFFSET_FOR_FUNCTOR_DESCRIPTOR]))

	/*
	** Macros to access the data in an equivalence type_functors,
	** the equivalent type of this type.
	*/

#define MR_TYPE_CTOR_FUNCTORS_EQUIV_OFFSET_FOR_TYPE	((Integer) 1)

#define MR_TYPE_CTOR_FUNCTORS_EQUIV_TYPE(Functors)			\
	((Functors)[MR_TYPE_CTOR_FUNCTORS_EQUIV_OFFSET_FOR_TYPE])

/*---------------------------------------------------------------------------*/

/*
** Macros and defintions for defining and dealing with the data structures
** created by type_ctor_layouts (these are the same vectors referred to
** by type_ctor_functors)
** 	- the functor descriptor, describing a single functor
** 	- the enum_vector, describing an enumeration
** 	- the no_tag_vector, describing a single functor 
*/

	/*
	** Macros for dealing with enum vectors.
	*/

typedef struct {
	int enum_or_comp_const;
	Word num_sharers;		
	ConstString functor1;
/* other functors follow, num_sharers of them.
** 	ConstString functor2;
** 	...
*/
} MR_TypeLayout_EnumVector;

#define MR_TYPE_CTOR_LAYOUT_ENUM_VECTOR_IS_ENUM(Vector)			\
	((MR_TypeLayout_EnumVector *) (Vector))->enum_or_comp_const

#define MR_TYPE_CTOR_LAYOUT_ENUM_VECTOR_NUM_FUNCTORS(Vector)		\
	((MR_TypeLayout_EnumVector *) (Vector))->num_sharers

#define MR_TYPE_CTOR_LAYOUT_ENUM_VECTOR_FUNCTOR_NAME(Vector, N)		\
	( (&((MR_TypeLayout_EnumVector *)(Vector))->functor1) [N] )


	/*
	** Macros for dealing with functor descriptors.
	**
	** XXX we might like to re-organize this structure so the
	**     variable length component isn't such a pain.
	*/

typedef struct {
	Integer		arity;
	Word		arg1;		
/* other functors follow, arity of them.
** 	Word		arg2;
** 	...
**	ConstString	functorname;
**	Word		tagbits;
**	Integer		num_extra_args; 	for exist quant args
**	Word		locn1;			type info locations
**	...
*/
} MR_TypeLayout_FunctorDescriptor;

#define MR_TYPE_CTOR_LAYOUT_FUNCTOR_DESCRIPTOR_OFFSET_FOR_ARITY	\
	((Integer) 0)
#define MR_TYPE_CTOR_LAYOUT_FUNCTOR_DESCRIPTOR_OFFSET_FOR_ARGS	((Integer) 1)
	/* Note, these offsets are from the end of the args */
#define MR_TYPE_CTOR_LAYOUT_FUNCTOR_DESCRIPTOR_OFFSET_FOR_FUNCTOR_NAME	\
		((Integer) 1)
#define MR_TYPE_CTOR_LAYOUT_FUNCTOR_DESCRIPTOR_OFFSET_FOR_FUNCTOR_TAG	\
		((Integer) 2)
#define MR_TYPE_CTOR_LAYOUT_FUNCTOR_DESCRIPTOR_OFFSET_FOR_EXIST_TYPEINFO_VARCOUNT \
		((Integer) 3)
#define MR_TYPE_CTOR_LAYOUT_FUNCTOR_DESCRIPTOR_OFFSET_FOR_EXIST_TYPECLASSINFO_VARCOUNT \
		((Integer) 4)
#define MR_TYPE_CTOR_LAYOUT_FUNCTOR_DESCRIPTOR_OFFSET_FOR_TYPE_INFO_LOCNS \
		((Integer) 5)

#define MR_TYPE_CTOR_LAYOUT_FUNCTOR_DESCRIPTOR_ARITY(V)			\
		((V)[MR_TYPE_CTOR_LAYOUT_FUNCTOR_DESCRIPTOR_OFFSET_FOR_ARITY])

#define MR_TYPE_CTOR_LAYOUT_FUNCTOR_DESCRIPTOR_ARGS(V)			\
		(V + MR_TYPE_CTOR_LAYOUT_FUNCTOR_DESCRIPTOR_OFFSET_FOR_ARGS)

#define MR_TYPE_CTOR_LAYOUT_FUNCTOR_DESCRIPTOR_FUNCTOR_NAME(V)		\
	((String) ((V)[MR_TYPE_CTOR_LAYOUT_FUNCTOR_DESCRIPTOR_ARITY(V) + \
	    MR_TYPE_CTOR_LAYOUT_FUNCTOR_DESCRIPTOR_OFFSET_FOR_FUNCTOR_NAME]))

#define MR_TYPE_CTOR_LAYOUT_FUNCTOR_DESCRIPTOR_TAG(V)			\
	((Word) ((V)[MR_TYPE_CTOR_LAYOUT_FUNCTOR_DESCRIPTOR_ARITY(V) +	\
		MR_TYPE_CTOR_LAYOUT_FUNCTOR_DESCRIPTOR_OFFSET_FOR_FUNCTOR_TAG]))

#define MR_TYPE_CTOR_LAYOUT_FUNCTOR_DESCRIPTOR_EXIST_TYPEINFO_VARCOUNT(V)	\
	((Word) ((V)[MR_TYPE_CTOR_LAYOUT_FUNCTOR_DESCRIPTOR_ARITY(V) +	\
		MR_TYPE_CTOR_LAYOUT_FUNCTOR_DESCRIPTOR_OFFSET_FOR_EXIST_TYPEINFO_VARCOUNT]))

#define MR_TYPE_CTOR_LAYOUT_FUNCTOR_DESCRIPTOR_EXIST_TYPECLASSINFO_VARCOUNT(V)	\
	((Word) ((V)[MR_TYPE_CTOR_LAYOUT_FUNCTOR_DESCRIPTOR_ARITY(V) +	\
		MR_TYPE_CTOR_LAYOUT_FUNCTOR_DESCRIPTOR_OFFSET_FOR_EXIST_TYPECLASSINFO_VARCOUNT]))

#define MR_TYPE_CTOR_LAYOUT_FUNCTOR_DESCRIPTOR_EXIST_VARCOUNT(V)	\
		MR_TYPE_CTOR_LAYOUT_FUNCTOR_DESCRIPTOR_EXIST_TYPEINFO_VARCOUNT(V) + MR_TYPE_CTOR_LAYOUT_FUNCTOR_DESCRIPTOR_EXIST_TYPECLASSINFO_VARCOUNT(V)

#define MR_TYPE_CTOR_LAYOUT_FUNCTOR_DESCRIPTOR_TYPE_INFO_LOCNS(V)	  \
	(((Word *)V) + 							  \
		MR_TYPE_CTOR_LAYOUT_FUNCTOR_DESCRIPTOR_ARITY((Word *)V) + \
		MR_TYPE_CTOR_LAYOUT_FUNCTOR_DESCRIPTOR_OFFSET_FOR_TYPE_INFO_LOCNS)

	/*
	** Macros for handling type info locations
	*/
#define MR_TYPE_INFO_LOCN_IS_INDIRECT(t) ((t) & (Unsigned) 1)
#define MR_TYPE_INFO_LOCN_INDIRECT_GET_TYPEINFO_NUMBER(t) (int) ((t) >> 7)
#define MR_TYPE_INFO_LOCN_INDIRECT_GET_ARG_NUMBER(t) \
	(int) (((t) >> 1) & (Unsigned) 63)
#define MR_TYPE_INFO_LOCN_DIRECT_GET_TYPEINFO_NUMBER(t) (int) ((t) >> 1)

	/*
	** Macros for dealing with shared remote vectors.
	*/

typedef struct {
	Word num_sharers;		
	Word functor_descriptor1;
/* other functor descriptors follow, num_sharers of them.
**	Word functor_descriptor2;
** 	...
*/
} MR_TypeLayout_SharedRemoteVector;

#define MR_TYPE_CTOR_LAYOUT_SHARED_REMOTE_VECTOR_NUM_SHARERS(Vector) 	\
	(((MR_TypeLayout_SharedRemoteVector *) (Vector))->num_sharers)

#define MR_TYPE_CTOR_LAYOUT_SHARED_REMOTE_VECTOR_GET_FUNCTOR_DESCRIPTOR( \
		Vector, N)						 \
	( (Word *) MR_strip_tag((&((MR_TypeLayout_SharedRemoteVector *)	 \
		(Vector))->functor_descriptor1) [N]) )
		
	/* 
	** Macros for dealing with no_tag vectors 
	**
	** (Note, we know the arity is 1).
	*/

typedef struct {
	int		is_no_tag;
	Word		arg;
	ConstString	name;
} MR_TypeLayout_NoTagVector;

#define MR_TYPE_CTOR_LAYOUT_NO_TAG_VECTOR_IS_NO_TAG(Vector)		\
		((MR_TypeLayout_NoTagVector *) (Vector))->is_no_tag

#define MR_TYPE_CTOR_LAYOUT_NO_TAG_VECTOR_ARITY(Vector)			\
		(1)

#define MR_TYPE_CTOR_LAYOUT_NO_TAG_VECTOR_ARGS(Vector)			\
		&(((MR_TypeLayout_NoTagVector *) (Vector))->arg)
		
#define MR_TYPE_CTOR_LAYOUT_NO_TAG_VECTOR_FUNCTOR_NAME(Vector)		\
		((MR_TypeLayout_NoTagVector *) (Vector))->name

	/* 
	** Macros for dealing with equivalent vectors 
	*/	

typedef struct {
	int	is_no_tag;		/* might be a no_tag */
	Word	equiv_type;
} MR_TypeLayout_EquivVector;

#define MR_TYPE_CTOR_LAYOUT_EQUIV_OFFSET_FOR_TYPE	((Integer) 1)

#define MR_TYPE_CTOR_LAYOUT_EQUIV_IS_EQUIV(Vector)			\
		(!((MR_TypeLayout_EquivVector *) (Vector))->is_no_tag)

#define MR_TYPE_CTOR_LAYOUT_EQUIV_TYPE(Vector)				\
		((MR_TypeLayout_EquivVector *) (Vector))->equiv_type

/*---------------------------------------------------------------------------*/

	/* 
	** Macros for retreiving things from type_infos.
	*/

#define MR_TYPEINFO_GET_TYPE_CTOR_INFO(TypeInfo)			\
	((MR_TypeCtorInfo) ((*(TypeInfo)) ? *(TypeInfo) : (Word) (TypeInfo)))

#define MR_TYPEINFO_GET_HIGHER_ARITY(TypeInfo)				\
	((Integer) (Word *) (TypeInfo)[TYPEINFO_OFFSET_FOR_PRED_ARITY]) 


/*---------------------------------------------------------------------------*/

/*
** definitions for accessing the representation of the
** Mercury typeclass_info
*/

#define	MR_typeclass_info_instance_arity(tci) \
	((Integer)(*(Word **)(tci))[0])
#define	MR_typeclass_info_num_superclasses(tci) \
	((Integer)(*(Word **)(tci))[1])
#define	MR_typeclass_info_num_type_infos(tci) \
	((Integer)(*(Word **)(tci))[2])
#define	MR_typeclass_info_class_method(tci, n) \
	((Code *)(*(Word **)tci)[(n+2)])
#define	MR_typeclass_info_arg_typeclass_info(tci, n) \
	(((Word *)(tci))[(n)])

	/*
	** The following have the same definitions. This is because 
	** the call to MR_typeclass_info_type_info must already have the
	** number of superclass_infos for the class added to it
	*/
#define	MR_typeclass_info_superclass_info(tci, n) \
	(((Word *)(tci))[MR_typeclass_info_instance_arity(tci) + (n)])
#define	MR_typeclass_info_type_info(tci, n) \
	(((Word *)(tci))[MR_typeclass_info_instance_arity(tci) + (n)])

/*---------------------------------------------------------------------------*/

int MR_compare_type_info(Word, Word);
Word MR_collapse_equivalences(Word);

/* 
** Functions for creating type_infos from pseudo_type_infos.
** See mercury_type_info.c for documentation on these.
*/

Word * MR_create_type_info(const Word *, const Word *);
Word * MR_create_type_info_maybe_existq(const Word *, const Word *,
		const Word *, const Word *);

/* for MR_make_type_info(), we keep a list of allocated memory cells */
struct MR_MemoryCellNode {
	void				*data;
	struct MR_MemoryCellNode	*next;
};

typedef struct MR_MemoryCellNode *MR_MemoryList;

Word * MR_make_type_info(const Word *term_type_info, 
	const Word *arg_pseudo_type_info, MR_MemoryList *allocated);
Word * MR_make_type_info_maybe_existq(const Word *term_type_info, 
	const Word *arg_pseudo_type_info, const Word *data_value, 
	const Word *functor_descriptor, MR_MemoryList *allocated) ;
void MR_deallocate(MR_MemoryList allocated_memory_cells);

/*---------------------------------------------------------------------------*/

/*
** definitions and functions for categorizing data representations.
*/

/*
** MR_DataRepresentation is the representation for a particular type
** constructor.  For the cases of MR_TYPE_CTOR_REP_DU and
** MR_TYPE_CTOR_REP_DU_USEREQ, the exact representation depends on the tag
** value -- lookup the tag value in type_ctor_layout to find out this
** information.
**
** 
*/
typedef enum MR_TypeCtorRepresentation {
	MR_TYPECTOR_REP_ENUM,
	MR_TYPECTOR_REP_ENUM_USEREQ,
	MR_TYPECTOR_REP_DU,
	MR_TYPECTOR_REP_DU_USEREQ,
	MR_TYPECTOR_REP_NOTAG,
	MR_TYPECTOR_REP_NOTAG_USEREQ,
	MR_TYPECTOR_REP_EQUIV,
	MR_TYPECTOR_REP_EQUIV_VAR,
	MR_TYPECTOR_REP_INT,
	MR_TYPECTOR_REP_CHAR,
	MR_TYPECTOR_REP_FLOAT,
	MR_TYPECTOR_REP_STRING,
	MR_TYPECTOR_REP_PRED,
	MR_TYPECTOR_REP_UNIV,
	MR_TYPECTOR_REP_VOID,
	MR_TYPECTOR_REP_C_POINTER,
	MR_TYPECTOR_REP_TYPEINFO,
	MR_TYPECTOR_REP_TYPECLASSINFO,
	MR_TYPECTOR_REP_ARRAY,
	MR_TYPECTOR_REP_SUCCIP,
	MR_TYPECTOR_REP_HP,
	MR_TYPECTOR_REP_CURFR,
	MR_TYPECTOR_REP_MAXFR,
	MR_TYPECTOR_REP_REDOFR,
	MR_TYPECTOR_REP_REDOIP,
	MR_TYPECTOR_REP_TRAIL_PTR,
	MR_TYPECTOR_REP_TICKET,
	/*
	** MR_TYPECTOR_REP_UNKNOWN should remain the last alternative;
	** MR_CTOR_REP_STATS depends on this.
	*/
	MR_TYPECTOR_REP_UNKNOWN
} MR_TypeCtorRepresentation;

/*
** If the MR_TypeCtorRepresentation is MR_TYPE_CTOR_REP_DU, we have a
** discriminated union type (other than a no-tag or enumeration).  Each
** tag may have a different representation.
*/
typedef enum MR_DiscUnionTagRepresentation {
	MR_DISCUNIONTAG_SHARED_LOCAL,
	MR_DISCUNIONTAG_UNSHARED,
	MR_DISCUNIONTAG_SHARED_REMOTE
} MR_DiscUnionTagRepresentation;

/*
** Return the tag representation used by the data with the given
** entry in the type_ctor_layout table.
*/

MR_DiscUnionTagRepresentation MR_get_tag_representation(Word layout_entry);

/*---------------------------------------------------------------------------*/

/* XXX these typedefs should include const [zs, 14 Sep 1999] */
typedef	Word *	MR_TypeCtorFunctors;
typedef	Word *	MR_TypeCtorLayout;

	/*
	** Structs defining the structure of type_ctor_infos.
	** A type_ctor_info describes the structure of a particular
	** type constructor.  One of these is generated for every
	** `:- type' declaration.
	*/

struct MR_TypeCtorInfo_struct {
	Integer				arity;
	Code				*unify_pred;
	Code				*index_pred;
	Code				*compare_pred;
		/* 
		** The representation that is used for this type
		** constructor -- e.g. an enumeration, or a builtin
		** type, or a no-tag type, etc.
		*/
	MR_TypeCtorRepresentation	type_ctor_rep;
		/*
		** The names, arity and argument types of all the
		** functors of this type if it is some sort of
		** discriminated union.
		*/
	MR_TypeCtorFunctors		type_ctor_functors;
		/*
		** The meanings of the primary tags of this type,
		** if it is a discriminated union.
		*/
	MR_TypeCtorLayout		type_ctor_layout;
	String				type_ctor_module_name;
	String				type_ctor_name;
	Integer				type_ctor_version;
};

typedef struct MR_TypeCtorInfo_struct *MR_TypeCtorInfo;

	/* 
	** Macros for retrieving things from type_ctor_infos.
	**
	** XXX zs: these macros should be deleted; the code using them
	** would be clearer if it referred to TypeCtorInfo fields directly.
	*/
#define MR_TYPE_CTOR_INFO_GET_TYPE_CTOR_FUNCTORS(TypeCtorInfo)		\
	((TypeCtorInfo)->type_ctor_functors)

#define MR_TYPE_CTOR_INFO_GET_TYPE_CTOR_LAYOUT(TypeCtorInfo)		\
	((TypeCtorInfo)->type_ctor_layout)

#define MR_TYPE_CTOR_INFO_GET_TYPE_CTOR_LAYOUT_ENTRY(TypeCtorInfo, Tag)	\
	((TypeCtorInfo)->type_ctor_layout[(Tag)])

#define MR_TYPE_CTOR_INFO_GET_TYPE_ARITY(TypeCtorInfo)			\
	((TypeCtorInfo)->arity)

#define MR_TYPE_CTOR_INFO_GET_TYPE_NAME(TypeCtorInfo)			\
	((TypeCtorInfo)->type_ctor_name)

#define MR_TYPE_CTOR_INFO_GET_TYPE_MODULE_NAME(TypeCtorInfo)		\
	((TypeCtorInfo)->type_ctor_module_name)

/*---------------------------------------------------------------------------*/
#endif /* not MERCURY_TYPEINFO_H */
