/*
** vim: ts=4 sw=4 expandtab
*/
/*
** Copyright (C) 2007 The University of Melbourne.
** This file may only be copied under the terms of the GNU Library General
** Public License - see the file COPYING.LIB in the Mercury distribution.
*/

/*
** File: mercury_region.h
** main author: Quan Phan
*/

#ifndef MERCURY_REGION_H
#define MERCURY_REGION_H

#include "mercury_types.h"

#ifdef MR_USE_REGIONS
#define MR_RBMM_DEBUG
/*
** See the documentation of MR_RBMM_DEBUG and MR_RBMM_PROFILING in
** mercury_conf_param.h.
*/

/*
** XXX: Many of these macros would be more efficient if they updated the
** pointer processed in each loop iteration using pointer increment operations
** instead of recomputing it each time from the pointer to the first element,
** and the loop variable  i.
**
** XXX Many of these macros would be more readable if they used array notation.
** For example, stack_pointer[offset] instead *(stack_pointer + offset),
** and &stack_pointer[offset] instead (stack_pointer + offset).
*/

/* XXX This should be made configurable when compiling a program. */
#define     MR_REGION_NUM_PAGES_TO_REQUEST                  100
#define     MR_REGION_PAGE_SPACE_SIZE                       256

/*
** The following constants should match the values of the Mercury compiler
** options with corresponding names.
*/

#define     MR_REGION_ITE_FRAME_FIXED_SIZE                  4

#define     MR_REGION_DISJ_FRAME_FIXED_SIZE                 4
#define     MR_REGION_DISJ_FRAME_DUMMY_SEQ_NUMBER           0

#define     MR_REGION_COMMIT_FRAME_FIXED_SIZE               4

#define     MR_REGION_SNAPSHOT_SIZE                         4

#define     MR_REGION_ITE_PROT_SIZE                         1
#define     MR_REGION_DISJ_PROT_SIZE                        0
#define     MR_REGION_COMMIT_SAVE_SIZE                      1

/*
** A region page contains an array (of MR_Word) to store program data and
** a pointer to the next to form a single-linked-list.  Note: the order of
** fields in this struct is important. We make use of the order for several
** computations (such as the address of a region).
*/

struct MR_RegionPage_Struct {
    /* The space to store program data. */
    MR_Word             MR_regionpage_space[MR_REGION_PAGE_SPACE_SIZE];

    /* Pointer to the next page to form the linked list. */
    MR_RegionPage       *MR_regionpage_next;

#ifdef MR_RBMM_PROFILING
    /*
    ** This is to count the number of words which are currently allocated into
    ** the region. It means that it will be reset at backtracking if the region
    ** is restored from its snapshot.
    */
    int                 MR_regionpage_allocated_size;
#endif
};

/*
** A region is implemented as a single-linked list of (region) pages.
** The information of the region itself (pointer to next available word,
** removal counter, some other operational data) is stored in its first page.
*/

struct MR_Region_Struct {
    /*
    ** Pointer to the last page of the region, i.e., the newest or last added
    ** page. This is needed when we need to enlarge the region.
    */
    MR_RegionPage                       *MR_region_last_page;

    /*
    ** Pointer to the next available word for allocation. Allocations into
    ** a region always occur at its last page therefore this pointer always
    ** points into the last page.
    */
    MR_Word                             *MR_region_next_available_word;

    /*
    ** The current number of words (in the last page) available for allocation
    ** into the region. When an allocation requires more words than what is
    ** available the region is extended by adding a new page.
    */
    MR_Word                             MR_region_available_space;

    /*
    ** Currently not used. To be used for implementing conditional removals
    ** of regions, i.e., the region is only actually removed when the counter
    ** equals to one.
    */
    unsigned int                        MR_region_removal_counter;

    /* Sequence number of the region. */
    MR_Word                             MR_region_sequence_number;

    /* If the region has been removed in forward execution. */
    MR_Word                             MR_region_logical_removed;

    /*
    ** NULL if the region is not protected by any if-then-else. Otherwise
    ** it points to region_ite_stack frame that protects it.
    */
    MR_RegionIteFixedFrame             *MR_region_ite_protected;

    /* If the region is saved at this frame in the region_commit_stack. */
    MR_RegionCommitFixedFrame          *MR_region_commit_frame;

    /*
    ** True if the region has been removed logically in a commit context and
    ** therefore needs to be destroyed at commit.
    */
    MR_Word                             MR_region_destroy_at_commit;

    MR_Region                           *MR_region_previous_region;
    MR_Region                           *MR_region_next_region;
};

struct MR_RegionIteFixedFrame_Struct {
    MR_RegionIteFixedFrame          *MR_riff_previous_ite_frame;
    MR_Region                       *MR_riff_saved_region_list;
    int                             MR_riff_num_prot_regions;
    int                             MR_riff_num_snapshots;
};

struct MR_RegionDisjFixedFrame_Struct {
    MR_RegionDisjFixedFrame         *MR_rdff_previous_disj_frame;
    MR_Region                       *MR_rdff_saved_region_list;
    MR_Word                         MR_rdff_disj_prot_seq_number;
    MR_Word                         MR_rdff_num_snapshots;
};

struct MR_RegionCommitFixedFrame_Struct {
    MR_RegionCommitFixedFrame       *MR_rcff_previous_commit_frame;
    MR_Word                         MR_rcff_saved_sequence_number;
    MR_RegionDisjFixedFrame         *MR_rcff_saved_disj_sp;
    MR_Word                         MR_rcff_num_saved_regions;
};

/*
** To save the current size of a region in preparation for instant reclaiming.
*/

struct MR_RegionSnapshot_Struct {
    MR_Region           *MR_snapshot_region;
    MR_RegionPage       *MR_snapshot_saved_last_page;
    MR_Word             *MR_snapshot_saved_next_available_word;
    MR_Word             MR_snapshot_saved_available_space;
};

/* Protection information in an ite frame. */
struct MR_RegionIteProtect_Struct {
    MR_Region           *MR_ite_prot_region;
};

/* Protection information in a disj frame. */
struct MR_RegionDisjProtect_Struct {
    MR_Region           *MR_disj_prot_region;
};

/* Save information in a commit frame */
struct MR_RegionCommitSave_Struct {
    MR_Region           *MR_commit_save_region;
};

/*
** The region runtime maintains a list of free pages, when a program needs
** a page for a region the page is taken from the list.
*/

extern MR_RegionPage    *MR_region_free_page_list;

/* The live regions are linked in a list. */
extern MR_Region        *MR_live_region_list;

extern MR_Word          MR_region_sequence_number;

/* Pointers to the top frames of ite, disj, and commit stacks. */
extern MR_RegionIteFixedFrame       *MR_region_ite_sp;
extern MR_RegionDisjFixedFrame      *MR_region_disj_sp;
extern MR_RegionCommitFixedFrame    *MR_region_commit_sp;

/*---------------------------------------------------------------------------*/

/* Create a region. */
extern  MR_Region       *MR_region_create_region(void);

/* Destroy a region, i.e., physically deallocate the region. */
extern  void            MR_region_destroy_region(MR_Region *);

/*
** Remove a region.
** If the region is not protected it is destroyed, otherwise it is only
** logically removed, i.e., we mark it as removed but not actually deallocate.
*/

extern  void            MR_region_remove_region(MR_Region *);
extern  void            MR_remove_undisjprotected_region_ite_then_semidet(
                            MR_Region *);
extern  void            MR_remove_undisjprotected_region_ite_then_nondet(
                            MR_Region *);

/* Allocate a number of words into a region. */
extern  MR_Word         *MR_region_alloc(MR_Region *, unsigned int);

#define     MR_alloc_in_region(dest, region, num)                           \
            MR_tag_alloc_in_region(dest, 0, region, num)                    \

#define     MR_tag_alloc_in_region(dest, tag, region, num)                  \
            do {                                                            \
                (dest) = (MR_Word) MR_mkword((tag), (MR_Word)               \
                    MR_region_alloc((MR_Region *) (region), (num)));        \
            } while (0)

extern  int             MR_region_is_disj_protected(MR_Region *region);

/*---------------------------------------------------------------------------*/
/*
** push_region_frame
*/

#define     MR_push_region_ite_frame(new_ite_sp)                            \
            do {                                                            \
                MR_RegionIteFixedFrame      *new_ite_frame;                 \
                                                                            \
                new_ite_frame = (MR_RegionIteFixedFrame *) (new_ite_sp);    \
                new_ite_frame->MR_riff_previous_ite_frame =                 \
                    MR_region_ite_sp;                                       \
                new_ite_frame->MR_riff_saved_region_list =                  \
                    MR_live_region_list;                                    \
                MR_region_ite_sp = new_ite_frame;                           \
                MR_region_debug_push_ite_frame(new_ite_frame);              \
            } while (0)

#define     MR_push_region_disj_frame(new_disj_sp)                          \
            do {                                                            \
                MR_RegionDisjFixedFrame     *new_disj_frame;                \
                                                                            \
                new_disj_frame = (MR_RegionDisjFixedFrame *) (new_disj_sp); \
                new_disj_frame->MR_rdff_previous_disj_frame =               \
                    MR_region_disj_sp;                                      \
                new_disj_frame->MR_rdff_saved_region_list =                 \
                    MR_live_region_list;                                    \
                new_disj_frame->MR_rdff_disj_prot_seq_number =              \
                    MR_region_sequence_number;                              \
                MR_region_disj_sp = new_disj_frame;                         \
                MR_region_debug_push_disj_frame(new_disj_frame);            \
            } while (0)

#define     MR_push_region_commit_frame(new_commit_sp)                      \
            do {                                                            \
                MR_RegionCommitFixedFrame   *new_commit_frame;              \
                                                                            \
                new_commit_frame =                                          \
                    (MR_RegionCommitFixedFrame *) (new_commit_sp);          \
                new_commit_frame->MR_rcff_previous_commit_frame =           \
                    MR_region_commit_sp;                                    \
                new_commit_frame->MR_rcff_saved_sequence_number =           \
                    MR_region_sequence_number;                              \
                new_commit_frame->MR_rcff_saved_disj_sp = MR_region_disj_sp;\
                MR_region_commit_sp = new_commit_frame;                     \
                MR_region_debug_push_commit_frame(new_commit_frame);        \
            } while (0)

/*---------------------------------------------------------------------------*/
/*
** region_fill_frame
*/
/*
** Save the region if it satisfies:
** (a) live before condition
** (c2) aren't already protected (ite_protected or disj_protected).
** If save the region, then set the ite_protected field in these regions
** to point to the frame.
*/
#define     MR_region_fill_ite_protect(ite_sp, region_ptr,                  \
                num_protected_regions, region_slot_reg)                     \
            do {                                                            \
                MR_Region *region;                                          \
                                                                            \
                region = (MR_Region *) (region_ptr);                        \
                if (!MR_region_is_disj_protected(region) &&                 \
                    region->MR_region_ite_protected == NULL)                \
                {                                                           \
                    *((MR_Word *) (region_slot_reg)) = (MR_Word) region;    \
                    (num_protected_regions)++;                              \
                    (region_slot_reg) = (MR_Word)                           \
                        (((MR_Word *) (region_slot_reg)) +                  \
                            MR_REGION_ITE_PROT_SIZE);                       \
                    region->MR_region_ite_protected =                       \
                        (MR_RegionIteFixedFrame *) (ite_sp);                \
                }                                                           \
            } while (0)

/*
** This is to prepare for instant reclaiming at the start of else. For instant
** reclaiming a region we save its current size by taking a snapshot of it. The
** natural question would be for which regions.  The very first
** criterion is whether a region will be destroyed right at the start of the
** else. It is because we need not to reclaim memory for those which will be
** destroyed anyway right after that. To decide if a region will be destroyed
** at the start of the else we need information at both compile-time and
** runtime. That is at compile-time we only know if the region is removed or
** not, and at runtime we will know if the region is protected from being
** destroyed. So,
** 1. Those that are removed and protected need to be saved.
** 2. Those that are not removed (so not destroyed) will need to be saved.
*/
/*
** XXX ite_sp is not used here.
*/
#define     MR_region_fill_ite_snapshot_removed(ite_sp, region_ptr,         \
                num_snapshots, snapshot_block)                              \
            do {                                                            \
                MR_Region   *region;                                        \
                                                                            \
                region = (MR_Region *) (region_ptr);                        \
                if (region->MR_region_ite_protected != NULL ||              \
                    MR_region_is_disj_protected(region))                    \
                {                                                           \
                    MR_save_snapshot(region, snapshot_block);               \
                    MR_next_snapshot_block(snapshot_block);                 \
                    (num_snapshots)++;                                      \
                } /* Else the region is not protected. */                   \
            } while (0)

#define     MR_region_fill_ite_snapshot_not_removed(ite_sp, region_ptr,     \
                num_snapshots, snapshot_block)                              \
            do {                                                            \
                MR_Region   *region;                                        \
                                                                            \
                region = (MR_Region *) (region_ptr);                        \
                MR_save_snapshot(region, (snapshot_block));                 \
                MR_next_snapshot_block(snapshot_block);                     \
                (num_snapshots)++;                                          \
            } while (0)

#define     MR_region_fill_disj_protect(disj_sp, region_ptr,                \
                num_protected_regions, protection_block)                    \
            do {                                                            \
            } while (0)

#define     MR_region_fill_disj_snapshot(disj_sp, region_ptr,               \
                num_snapshots, snapshot_block)                              \
            do {                                                            \
                MR_Region   *region;                                        \
                                                                            \
                region = (MR_Region *) (region_ptr);                        \
                MR_save_snapshot(region, (snapshot_block));                 \
                MR_next_snapshot_block(snapshot_block);                     \
                (num_snapshots)++;                                          \
            } while (0)

/*
** Save the live and unprotected regions which are input to the commit goal
** into the top commit stack frame.
** Set the commit_frame field in these regions to point to the frame.
*/
#define     MR_region_fill_commit(commit_sp, region_ptr,                    \
                    num_saved_region_reg, region_slot_reg)                  \
            do {                                                            \
                MR_Region   *region;                                        \
                                                                            \
                region = (MR_Region *) (region_ptr);                        \
                if (!MR_region_is_disj_protected(region) &&                 \
                    region->MR_region_ite_protected == NULL)                \
                {                                                           \
                    *((MR_Word *) (region_slot_reg)) = (MR_Word) region;    \
                    num_saved_region_reg++;                                 \
                    (region_slot_reg) = (MR_Word)                           \
                        (((MR_Word *) (region_slot_reg)) +                  \
                            MR_REGION_COMMIT_SAVE_SIZE);                    \
                    region->MR_region_commit_frame =                        \
                        (MR_RegionCommitFixedFrame *) (commit_sp);          \
                }                                                           \
            } while (0)

/*---------------------------------------------------------------------------*/
/*
** region_set_fixed_slot
*/
#define     MR_region_set_ite_num_protects(ite_sp, num)                     \
            do {                                                            \
                MR_RegionIteFixedFrame      *top_ite_frame;                 \
                                                                            \
                top_ite_frame = (MR_RegionIteFixedFrame *) (ite_sp);        \
                top_ite_frame->MR_riff_num_prot_regions = (num);            \
                MR_region_debug_ite_frame_protected_regions(top_ite_frame); \
            } while (0)

#define     MR_region_set_ite_num_snapshots(ite_sp, num)                    \
            do {                                                            \
                MR_RegionIteFixedFrame      *top_ite_frame;                 \
                                                                            \
                top_ite_frame = (MR_RegionIteFixedFrame *) (ite_sp);        \
                top_ite_frame->MR_riff_num_snapshots = (num);               \
                MR_region_debug_ite_frame_snapshots(top_ite_frame);         \
            } while (0)

#define     MR_region_set_disj_num_protects(disj_sp, num)                   \
            do {                                                            \
            } while (0)

#define     MR_region_set_disj_num_snapshots(disj_sp, num)                  \
            do {                                                            \
                MR_RegionDisjFixedFrame     *top_disj_frame;                \
                                                                            \
                top_disj_frame = (MR_RegionDisjFixedFrame *) (disj_sp);     \
                top_disj_frame->MR_rdff_num_snapshots = (num);              \
                MR_region_debug_disj_frame_snapshots(top_disj_frame);       \
            } while (0)

#define     MR_region_set_commit_num_entries(commit_sp, num)                \
            do {                                                            \
                MR_RegionCommitFixedFrame   *top_commit_frame;              \
                                                                            \
                top_commit_frame =                                          \
                    (MR_RegionCommitFixedFrame *) (commit_sp);              \
                top_commit_frame->MR_rcff_num_saved_regions = (num);        \
                MR_region_debug_commit_frame_saved_regions(                 \
                    top_commit_frame);                                      \
            } while (0)

/*---------------------------------------------------------------------------*/
/*
** use_and_maybe_pop_region_frame
*/

/*
** The next two macros are to remove each protected region at the start of the
** then part. If the condition is semidet we just need to destroy all the
** protected regions (whose are not disj-protected).
** If the condition is nondet we have to do 2 more things:
**  + 1. check if a protected region has already been destroyed
**  + 2. if we destroy a protected region, we have to nullify its
**  corresponding entry in the ite frame.
*/
#define     MR_use_region_ite_then_semidet(ite_sp)                          \
            do {                                                            \
                MR_RegionIteFixedFrame      *top_ite_frame;                 \
                MR_RegionIteProtect         *ite_prot;                      \
                int                         i;                              \
                                                                            \
                top_ite_frame = (MR_RegionIteFixedFrame *) (ite_sp);        \
                ite_prot = (MR_RegionIteProtect *) ( (ite_sp) +             \
                    MR_REGION_ITE_FRAME_FIXED_SIZE);                        \
                for (i = 0; i < top_ite_frame->MR_riff_num_prot_regions;    \
                        i++, ite_prot++) {                                  \
                    MR_remove_undisjprotected_region_ite_then_semidet(      \
                        ite_prot->MR_ite_prot_region);                      \
                }                                                           \
                MR_pop_region_ite_frame(top_ite_frame);                     \
            } while (0)

#define     MR_use_region_ite_then_nondet(ite_sp)                           \
            do {                                                            \
                MR_RegionIteFixedFrame      *top_ite_frame;                 \
                MR_RegionIteProtect         *ite_prot;                      \
                int                         i;                              \
                                                                            \
                top_ite_frame = (MR_RegionIteFixedFrame *) (ite_sp);        \
                ite_prot = (MR_RegionIteProtect *) ( (ite_sp) +             \
                    MR_REGION_ITE_FRAME_FIXED_SIZE);                        \
                for (i = 0; i < top_ite_frame->MR_riff_num_prot_regions;    \
                        i++, ite_prot++) {                                  \
                    if (ite_prot->MR_ite_prot_region != NULL) {             \
                        MR_remove_undisjprotected_region_ite_then_nondet(   \
                            ite_prot->MR_ite_prot_region);                  \
                    }                                                       \
                }                                                           \
            } while (0)

#define     MR_use_region_ite_else_semidet(ite_sp)                          \
            do {                                                            \
                MR_RegionIteFixedFrame      *top_ite_frame;                 \
                                                                            \
                top_ite_frame = (MR_RegionIteFixedFrame *) (ite_sp);        \
                MR_region_process_at_ite_else(top_ite_frame);               \
            } while (0)

#define     MR_use_region_ite_else_nondet(ite_sp)                           \
            do {                                                            \
                MR_RegionIteFixedFrame      *top_ite_frame;                 \
                                                                            \
                top_ite_frame = (MR_RegionIteFixedFrame *) (ite_sp);        \
                MR_region_process_at_ite_else(top_ite_frame);               \
            } while (0)

/*
** XXX  What am I supposed to do here?
** I think it should be exactly the same as the process at the start of
** any else branch, i.e., after the condition fails (to produce any solution).
*/
#define     MR_use_region_ite_nondet_cond_fail(ite_sp)                      \
            do {                                                            \
                MR_RegionIteFixedFrame      *top_ite_frame;                 \
                                                                            \
                top_ite_frame = (MR_RegionIteFixedFrame *) (ite_sp);        \
                MR_region_process_at_ite_else(top_ite_frame)                \
            } while (0)

#define     MR_use_region_disj_later(disj_sp)                               \
            do {                                                            \
                MR_RegionDisjFixedFrame     *top_disj_frame;                \
                                                                            \
                top_disj_frame = (MR_RegionDisjFixedFrame *) (disj_sp);     \
                MR_region_disj_restore_from_snapshots(top_disj_frame);      \
                MR_region_disj_destroy_new_regions(top_disj_frame);         \
            } while (0)

#define     MR_use_region_disj_last(disj_sp)                                \
            do {                                                            \
                MR_RegionDisjFixedFrame     *top_disj_frame;                \
                                                                            \
                top_disj_frame = (MR_RegionDisjFixedFrame *) (disj_sp);     \
                MR_region_disj_restore_from_snapshots(top_disj_frame);      \
                MR_region_disj_destroy_new_regions(top_disj_frame);         \
                MR_region_disj_unprotect_regions(top_disj_frame);           \
                MR_pop_region_disj_frame(top_disj_frame);                   \
            } while (0)

#define     MR_use_region_commit_success(commit_sp)                         \
            do {                                                            \
                MR_RegionCommitFixedFrame       *top_commit_frame;          \
                MR_RegionCommitSave             *first_commit_save;         \
                                                                            \
                top_commit_frame =                                          \
                    (MR_RegionCommitFixedFrame *) (commit_sp);              \
                first_commit_save = (MR_RegionCommitSave *) (               \
                    (commit_sp) + MR_REGION_COMMIT_FRAME_FIXED_SIZE);       \
                                                                            \
                MR_region_debug_commit_frame(top_commit_frame);             \
                                                                            \
                MR_commit_success_destroy_marked_new_regions(               \
                    top_commit_frame->MR_rcff_saved_sequence_number);       \
                MR_commit_success_destroy_marked_saved_regions(             \
                    top_commit_frame->MR_rcff_num_saved_regions,            \
                    first_commit_save);                                     \
                MR_region_disj_sp = top_commit_frame->MR_rcff_saved_disj_sp;\
                MR_pop_region_commit_frame(top_commit_frame);               \
            } while (0)

/*
** Commit failure means that the goal in the commit operation has failed.
** During this execution, all of the regions which are live before and removed
** inside the commit operation were saved at the commit frame because none of
** them were protected.
** We reset any changes to the commit-related state of these saved regions
** i.e., commit_frame and destroy_at_commit, to NULL and false, respectively.
** Then the top commit frame is popped.
*/
#define     MR_use_region_commit_failure(commit_sp)                         \
            do {                                                            \
                MR_RegionCommitFixedFrame       *top_commit_frame;          \
                MR_RegionCommitSave             *commit_save;               \
                MR_Region                       *region;                    \
                int                             i;                          \
                                                                            \
                top_commit_frame =                                          \
                    (MR_RegionCommitFixedFrame *) (commit_sp);              \
                commit_save = (MR_RegionCommitSave *) ( (commit_sp) +       \
                    MR_REGION_COMMIT_FRAME_FIXED_SIZE);                     \
                for (i = 0; i < top_commit_frame->MR_rcff_num_saved_regions;\
                        i++, commit_save++) {                               \
                    region = commit_save->MR_commit_save_region;            \
                    if (region != NULL) {                                   \
                        region->MR_region_commit_frame = NULL;              \
                        region->MR_region_destroy_at_commit = MR_FALSE;     \
                    }                                                       \
                }                                                           \
                MR_pop_region_commit_frame(top_commit_frame);               \
            } while (0)

extern  void    MR_commit_success_destroy_marked_saved_regions(
                    MR_Word number_of_saved_regions,
                    MR_RegionCommitSave *first_commit_save);

extern  void    MR_commit_success_destroy_marked_new_regions(
                    MR_Word saved_region_seq_number);

/*---------------------------------------------------------------------------*/

#define     MR_pop_region_ite_frame(top_ite_frame)                          \
            do {                                                            \
                MR_region_ite_sp =                                          \
                    top_ite_frame->MR_riff_previous_ite_frame;              \
            } while (0)

#define     MR_pop_region_disj_frame(top_disj_frame)                        \
            do {                                                            \
                MR_region_disj_sp =                                         \
                    top_disj_frame->MR_rdff_previous_disj_frame;            \
            } while (0)

#define     MR_pop_region_commit_frame(top_commit_frame)                    \
            do {                                                            \
                MR_region_commit_sp =                                       \
                    top_commit_frame->MR_rcff_previous_commit_frame;        \
            } while (0)

/*---------------------------------------------------------------------------*/
/* Helpers for ite support. */

/*
** At the start of else, we
** 1. unprotect the protected regions,
** 2. instant reclaiming using snapshots,
** 3. instant reclaiming by destroying new regions created in the condition,
** 4. pop the current ite frame.
*/
#define     MR_region_process_at_ite_else(top_ite_frame)                    \
            do {                                                            \
                MR_region_ite_unprotect(top_ite_frame);                     \
                MR_region_ite_restore_from_snapshots(top_ite_frame);        \
                MR_region_ite_destroy_new_regions(top_ite_frame);           \
                MR_pop_region_ite_frame(top_ite_frame);                     \
            } while (0)

/*
** Unprotect the protected regions at the beginning of the else part.
*/
#define     MR_region_ite_unprotect(top_ite_frame)                          \
            do {                                                            \
                MR_RegionIteProtect     *ite_prot;                          \
                MR_Region               *protected_region;                  \
                int                     i;                                  \
                                                                            \
                MR_region_debug_ite_frame(top_ite_frame);                   \
                ite_prot = (MR_RegionIteProtect *) (                        \
                    ( (MR_Word *) (top_ite_frame) ) +                       \
                    MR_REGION_ITE_FRAME_FIXED_SIZE);                        \
                for (i = 0; i < top_ite_frame->MR_riff_num_prot_regions;    \
                        i++, ite_prot++) {                                  \
                    protected_region = ite_prot->MR_ite_prot_region;        \
                    /* Try to protect the region by an outer condition. */  \
                    protected_region->MR_region_ite_protected =             \
                        top_ite_frame->MR_riff_previous_ite_frame;          \
                    MR_region_debug_region_struct_removal_info(             \
                        protected_region);                                  \
                }                                                           \
            } while (0)

#define     MR_region_ite_restore_from_snapshots(top_ite_frame)             \
            do {                                                            \
                MR_RegionSnapshot       *first_snapshot;                    \
                MR_Word                 protection_size;                    \
                                                                            \
                protection_size = top_ite_frame->MR_riff_num_prot_regions * \
                    MR_REGION_ITE_PROT_SIZE;                                \
                first_snapshot = (MR_RegionSnapshot *) (                    \
                    ( (MR_Word *) (top_ite_frame) ) +                       \
                    MR_REGION_ITE_FRAME_FIXED_SIZE + protection_size);      \
                MR_restore_snapshots(top_ite_frame->MR_riff_num_snapshots,  \
                    first_snapshot);                                        \
            } while (0)

#define     MR_region_ite_destroy_new_regions(top_ite_frame)                \
            MR_region_frame_destroy_new_regions(                            \
                top_ite_frame->MR_riff_saved_region_list)

/*---------------------------------------------------------------------------*/
/* Helpers for nondet disjunction support. */

/*
** At any non-first disjunct, try instant reclaiming from snapshots.
*/
#define     MR_region_disj_restore_from_snapshots(top_disj_frame)           \
            do {                                                            \
                MR_RegionSnapshot       *first_snapshot;                    \
                                                                            \
                first_snapshot = (MR_RegionSnapshot *) (                    \
                    (MR_Word *) (top_disj_frame) +                          \
                    MR_REGION_DISJ_FRAME_FIXED_SIZE);                       \
                MR_restore_snapshots(top_disj_frame->MR_rdff_num_snapshots, \
                    first_snapshot);                                        \
            } while (0)

/*
** At any non-first disjunct, try instant reclaiming by destroying new
** regions.
*/
#define     MR_region_disj_destroy_new_regions(top_disj_frame)              \
            MR_region_frame_destroy_new_regions(                            \
                top_disj_frame->MR_rdff_saved_region_list)

/*
** At the last disjunct, we do not disj-protect the regions anymore.
*/
#define     MR_region_disj_unprotect_regions(top_disj_frame)                \
            do {                                                            \
                top_disj_frame->MR_rdff_disj_prot_seq_number =              \
                    MR_REGION_DISJ_FRAME_DUMMY_SEQ_NUMBER;                  \
            } while (0)

/*---------------------------------------------------------------------------*/

#define     MR_save_snapshot(region, snapshot_block)                        \
            do {                                                            \
                MR_RegionSnapshot *snapshot;                                \
                                                                            \
                snapshot = (MR_RegionSnapshot *) (snapshot_block);          \
                snapshot->MR_snapshot_region = (region);                    \
                snapshot->MR_snapshot_saved_last_page =                     \
                    (region)->MR_region_last_page;                          \
                snapshot->MR_snapshot_saved_next_available_word =           \
                    (region)->MR_region_next_available_word;                \
                snapshot->MR_snapshot_saved_available_space =               \
                    (region)->MR_region_available_space;                    \
            } while (0)

#define     MR_next_snapshot_block(snapshot_block) (                        \
                (snapshot_block) = (MR_Word)                                \
                    (((MR_RegionSnapshot *) (snapshot_block) ) + 1)         \
            )

/*
** XXX For profiling:
** One correct way to reset the allocated_size is to save it in the snapshot
** so that here we have the old value right away. But having an extra slot
** in the disj frame causes changes at other places. From the snapshot
** information (as it is now) we can only compute the old value correctly if
** there is no wasteful space at the end of the region's pages. Therefore the
** allocated_size sometimes is not realiable.
*/

#define     MR_restore_snapshots(num_snapshots, first_snapshot)             \
            do {                                                            \
                MR_RegionSnapshot   *snapshot;                              \
                MR_Region           *restoring_region;                      \
                MR_RegionPage       *saved_last_page;                       \
                MR_RegionPage       *first_new_page;                        \
                int                 i;                                      \
                                                                            \
                snapshot = first_snapshot;                                  \
                for (i = 0; i < (num_snapshots); i++, snapshot++) {         \
                    restoring_region = snapshot->MR_snapshot_region;        \
                    saved_last_page = snapshot->MR_snapshot_saved_last_page;\
                    first_new_page = saved_last_page->MR_regionpage_next;   \
                    /* Collect profiling information. */                    \
                    MR_region_profile_restore_from_snapshot(snapshot);      \
                                                                            \
                    if (first_new_page != NULL) {                           \
                        MR_region_return_page_list(first_new_page,          \
                            restoring_region->MR_region_last_page);         \
                        restoring_region->MR_region_last_page =             \
                            saved_last_page;                                \
                    } /* else no new page added. */                         \
                    restoring_region->MR_region_next_available_word =       \
                        snapshot->MR_snapshot_saved_next_available_word;    \
                    restoring_region->MR_region_available_space =           \
                        snapshot->MR_snapshot_saved_available_space;        \
                }                                                           \
            } while(0)

#define     MR_region_frame_destroy_new_regions(saved_most_recent_region)   \
            do {                                                            \
                MR_Region       *region;                                    \
                MR_Region       *next_region;                               \
                                                                            \
                region = MR_live_region_list;                               \
                while (region != saved_most_recent_region) {                \
                    next_region = region->MR_region_next_region;            \
                    /* We destroy regions upto before the saved one. */     \
                    MR_region_destroy_region(region);                       \
                    region = next_region;                                   \
                }                                                           \
                MR_live_region_list = saved_most_recent_region;             \
            } while (0)

/* from_page must not be NULL. */
#define     MR_region_return_page_list(from_page, to_page)                  \
            do {                                                            \
                (to_page)->MR_regionpage_next = MR_region_free_page_list;   \
                MR_region_free_page_list = (from_page);                     \
            } while (0)

/*---------------------------------------------------------------------------*/
/* Debug RBMM messages. */

#ifdef MR_RBMM_DEBUG
    #define     MR_region_debug_create_region(region)                       \
                MR_region_create_region_msg(region)

    #define     MR_region_debug_try_remove_region(region)                   \
                MR_region_try_remove_region_msg(region)

    #define     MR_region_debug_region_struct_removal_info(region)          \
                MR_region_region_struct_removal_info_msg(region)

    #define     MR_region_debug_destroy_region(region)                      \
                MR_region_destroy_region_msg(region)

/* Debug ite frame messages. */
    #define     MR_region_debug_push_ite_frame(ite_sp)                      \
                MR_region_push_ite_frame_msg(ite_sp)

    #define     MR_region_debug_ite_frame(ite_sp);                          \
                MR_region_ite_frame_msg(ite_sp)

    #define     MR_region_debug_ite_frame_protected_regions(ite_sp);        \
                MR_region_ite_frame_protected_regions_msg(ite_sp)

    #define     MR_region_debug_ite_frame_snapshots(ite_sp);                \
                MR_region_ite_frame_snapshots_msg(ite_sp)

/* Debug disj frame messages. */
    #define     MR_region_debug_push_disj_frame(disj_sp)                    \
                MR_region_push_disj_frame_msg(disj_sp)

    #define     MR_region_debug_disj_frame(disj_sp)                         \
                MR_region_disj_frame_msg(disj_sp)

    #define     MR_region_debug_disj_frame_protected_regions(disj_sp);      \
                MR_region_disj_frame_protected_regions_msg(disj_sp);

    #define     MR_region_debug_disj_frame_snapshots(disj_sp);              \
                MR_region_disj_frame_snapshots_msg(disj_sp);

/* Debug commit frame messages. */
    #define     MR_region_debug_push_commit_frame(frame)                    \
                MR_region_push_commit_frame_msg(frame)

    #define     MR_region_debug_commit_frame(frame)                         \
                MR_region_commit_frame_msg(frame)

    #define     MR_region_debug_commit_frame_saved_regions(commit_sp);      \
                MR_region_commit_frame_saved_regions_msg(commit_sp)

#else   /* MR_RBMM_DEBUG */
    #define     MR_region_debug_create_region(region)                       \
                ((void) 0)

    #define     MR_region_debug_try_remove_region(region)                   \
                ((void) 0)


    #define     MR_region_debug_region_struct_removal_info(region)          \
                ((void) 0)

    #define     MR_region_debug_destroy_region(region)                      \
                ((void) 0)

    #define     MR_region_debug_push_ite_frame(frame)                       \
                ((void) 0)

    #define     MR_region_debug_ite_frame(ite_sp);                          \
                ((void) 0)

    #define     MR_region_debug_ite_frame_protected_regions(ite_sp);        \
                ((void) 0)

    #define     MR_region_debug_ite_frame_snapshots(ite_sp);                \
                ((void) 0)

    #define     MR_region_debug_push_disj_frame(disj_sp)                    \
                ((void) 0)

    #define     MR_region_debug_disj_frame(frame)                           \
                ((void) 0)

    #define     MR_region_debug_disj_frame_snapshots(disj_sp);              \
                ((void) 0)

    #define     MR_region_debug_push_commit_frame(frame)                    \
                ((void) 0)

    #define     MR_region_debug_commit_frame(frame)                         \
                ((void) 0)

    #define     MR_region_debug_commit_frame_saved_regions(commit_sp)       \
                ((void) 0)

#endif /* MR_RBMM_DEBUG */

extern  void    MR_region_create_region_msg(MR_Region *region);
extern  void    MR_region_try_remove_region_msg(MR_Region *region);
extern  void    MR_region_region_struct_removal_info_msg(MR_Region *region);
extern  void    MR_region_destroy_region_msg(MR_Region *region);
extern  void    MR_region_logically_remove_region_msg(MR_Region *region);

extern  void    MR_region_push_ite_frame_msg(MR_RegionIteFixedFrame *ite_frame);
extern  void    MR_region_ite_frame_msg(MR_RegionIteFixedFrame *ite_frame);
extern  void    MR_region_ite_frame_protected_regions_msg(
                    MR_RegionIteFixedFrame *ite_frame);
extern  void    MR_region_ite_frame_snapshots_msg(
                    MR_RegionIteFixedFrame *ite_frame);

extern  void    MR_region_push_disj_frame_msg(
                    MR_RegionDisjFixedFrame *disj_frame);
extern  void    MR_region_disj_frame_msg(MR_RegionDisjFixedFrame *disj_frame);
extern  void    MR_region_disj_frame_snapshots_msg(
                    MR_RegionDisjFixedFrame *disj_frame);

extern  void    MR_region_push_commit_frame_msg(
                    MR_RegionCommitFixedFrame *commit_frame);
extern  void    MR_region_commit_frame_msg(
                    MR_RegionCommitFixedFrame *commit_frame);
extern  void    MR_region_commit_frame_saved_regions_msg(
                    MR_RegionCommitFixedFrame *commit_frame);
extern  void    MR_region_commit_success_destroy_marked_regions_msg(
                    int saved_seq_number, int number_of_saved_regions,
                    MR_RegionCommitFixedFrame *commit_frame);

/*---------------------------------------------------------------------------*/
/* Profiling RBMM. */

#ifdef MR_RBMM_PROFILING

/*
** This is the profiling wish list, not all of them have been yet collected.
** - How many words are allocated
** - Maximum number of words
** - How many regions are allocated
** - Maximum number of regions
** - Size of the biggest region
** - How many regions are saved at commit entries
** - How many regions are protected at entry to a condition
** - How many snapshots are saved at entry to a condition
** - How many regions are protected at entry to a disj goal
** - How many snapshots are saved at entry to a disj goal
** - How many pages are requested from the OS
** - Time profiling: compile-time and runtime
*/

struct MR_RegionProfUnit_Struct {
    int        MR_rbmmpu_current;
    int        MR_rbmmpu_max;
    int        MR_rbmmpu_total;
};

extern MR_RegionProfUnit    MR_rbmmp_words_used;
extern MR_RegionProfUnit    MR_rbmmp_regions_used;
extern MR_RegionProfUnit    MR_rbmmp_pages_used;
extern unsigned int         MR_rbmmp_page_requested;
extern unsigned int         MR_rbmmp_biggest_region_size;
extern MR_RegionProfUnit    MR_rbmmp_regions_saved_at_commit;
extern unsigned int         MR_rbmmp_regions_protected_at_ite;
extern unsigned int         MR_rbmmp_snapshots_saved_at_ite;
extern unsigned int         MR_rbmmp_regions_protected_at_disj;
extern unsigned int         MR_rbmmp_snapshots_saved_at_disj;
extern double               MR_rbmmp_page_utilized;

#endif /* MR_RBMM_PROFILING. */

extern  void    MR_region_update_profiling_unit(
                    MR_RegionProfUnit *profiling_unit, int quantity);
extern  void    MR_region_profile_destroyed_region(MR_Region *);
extern  void    MR_region_profile_restore_from_snapshot(MR_RegionSnapshot *);
extern  int     MR_region_get_number_of_pages(MR_RegionPage *,
                    MR_RegionPage *);
extern  void    MR_region_print_profiling_info(void);

/*---------------------------------------------------------------------------*/

#endif  /* MR_USE_REGIONS */

#endif  /* MERCURY_REGION_H */