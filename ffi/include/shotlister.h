// The whole surface the Mac app sees. Four functions, JSON out.
//
// Everything the app can do goes through sl_call, which hands the command to
// the engine — so the app cannot write a state the engine would not allow.

#ifndef SHOTLISTER_H
#define SHOTLISTER_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct Handle Handle;

/// Opens the project at `path`. If nothing is there yet, creates one with the
/// Daybreak list in it. Returns NULL if it could not be opened.
Handle *sl_open(const char *path);

/// Opens a project as a **named device**. Every machine must call itself
/// something different: sync tells devices apart to know whether two edits
/// were made in knowledge of each other, and a device never writes another
/// device's changes into its own log. The id belongs to the shell — one per
/// machine, made once and remembered. 0 means "no opinion" and behaves as
/// sl_open does.
Handle *sl_open_as(const char *path, unsigned long long device);

/// Opens a project as a named device, saying **which machine** that name
/// belongs to. Ref 186.
///
/// A name is remembered in preferences, and preferences are what Migration
/// Assistant copies onto a new Mac — so two machines can end up insisting they
/// are one device, and edits made on both in the same moment are then thrown
/// away as duplicates of each other with nothing said. A machine is the
/// hardware itself and cannot be copied. Pass the platform UUID, hashed.
///
/// When two machines claim one name, the view carries `project.deviceClash`:
/// one sentence to put on screen. 0 means "no opinion" — no mark left, nothing
/// checked, exactly as every build before this one behaved.
Handle *sl_open_as_installed(const char *path, unsigned long long device,
                             unsigned long long installation);

/// Why the last sl_open failed, or an empty string. Owned by the caller.
char *sl_problem(void);

/// Sends one tab-delimited command and returns its JSON reply.
/// The caller owns the reply and must pass it to sl_free.
char *sl_call(Handle *handle, const char *line);

/// Frees a reply returned by sl_call.
void sl_free(char *reply);

/// Works out Auto's layout for the printed table from what a
/// `tablelayout … defer=1` call measured and handed back as a ticket. Touches
/// no project, so it may run on any thread — the measuring is on the
/// caller's, the deciding is here. Returns the plan's JSON (an error reply
/// for a ticket already used or never given). Owned by the caller: sl_free.
char *sl_solve_layout(unsigned long long ticket);

/// Closes a project opened by sl_open.
void sl_close(Handle *handle);

#ifdef __cplusplus
}
#endif

#endif
