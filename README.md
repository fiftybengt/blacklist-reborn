# Blacklist Reborn

A World of Warcraft **3.3.5a (Wrath of the Lich King)** addon that keeps a list of players you never want to group with again, and tells you when one of them turns up.

It is a ground-up overhaul of the classic *Black List* addon by Logan / ElrickEnonimis: no more warning spam, no chat filtering, working raid support, a full chat command set, and none of the interface taint that used to break Blizzard's own menus.

---

## Features

### Notifications that stay quiet until they matter
You are notified in exactly two situations:

- **A blacklisted player invites you to a group.** The warning shows, but the invite is left alone. You decide whether to accept.
- **You join a party or raid that contains a blacklisted player** (or one joins yours). You get one notice per player per group. Roster changes don't repeat it, and a player who leaves and comes back is announced again.

Each notice can play a sound, appear in the middle of the screen, and print to chat along with the reason you blacklisted them. All three can be switched off.

Nothing is ever blocked. Whispers, party, raid, guild and channel messages from blacklisted players come through exactly as normal.

### Adding players
- **Right-click any player** in party frames, raid frames, the target frame, your friends list, the chat channel roster, or on a name in chat. Choose **Add to Blacklist** from the small panel under the menu. **Guild Invite** and **Add to Friends** are there too.
- **`/bl add`** blacklists your current target, or **`/bl add <name> <reason>`** adds anyone by name.
- The **Add Player** button in the window does the same, and asks for a name if you have no target.

### Cross-realm aware
Dungeon Finder groups mix realms. Entries remember the realm, so blacklisting *Bob* from another realm doesn't flag the *Bob* on yours. The list shows them as `Bob (Realm)`.

### The Blacklist window
Open it with `/bl`, the **Blacklist** tab on the Friends frame, or a keybinding.

- Scrollable, alphabetical list of everyone you've blacklisted.
- Details panel for each player: level, class, race, faction crest, the date you added them, and a free-text **reason** (up to 500 characters) that saves as you type.
- **Warn Me** checkbox per player. Untick it to keep someone on the list without getting notified.
- **Edit** level, class and race by hand, for players you added by name.
- **List Group** button to check your current group at a glance.

### Checking and warning your group
- **`/bl list`** shows which members of your current raid (or party) are blacklisted, with reasons. Only you see it.
- **`/bl list -g`** does the same for your whole guild, offline members included.
- **`/bl warn`** tells your group, in raid chat if you're in a raid and party chat otherwise, which of its members are blacklisted and why:
  ```
  On my blacklist: Bob - ninja looted; Kev (Frostmourne) - left mid-boss
  ```
  Long reasons are shortened to fit, and messages are spaced out so the server won't throttle them.

---

## Commands

All commands start with `/bl` (or `/blacklist`). Flags always start with a dash.

| Command | What it does |
|---|---|
| `/bl` | Open or close the Blacklist window |
| `/bl help` | Show the command list |
| `/bl add [name] [reason]` | Blacklist a player by name, or your target if no name is given |
| `/bl remove [name]` | Remove a player by name, or your target |
| `/bl list` | List blacklisted players in your raid or party (only you see it) |
| `/bl list -g` | List blacklisted players in your guild (only you see it) |
| `/bl warn` | Announce blacklisted group members to raid chat, or party chat |
| `/bl warn -p` | Announce to party chat |
| `/bl warn -r` | Announce to raid chat |
| `/bl warn -g` | Announce blacklisted guild members to guild chat |
| `/bl options` | Open the options panel |

`/bl -p`, `/bl -r` and `/bl -g` work as shortcuts for `/bl warn -p|-r|-g`. The old `/removebl` still works and points you to `/bl remove`.

---

## Options

Open with `/bl options` or the **Options** button in the window.

| Option | Default | Effect |
|---|---|---|
| Play Sound | On | Play a sound with each notification |
| Warn at Center | On | Show the notification in the middle of the screen |
| Show in Chat | On | Print the notification and the reason to your chat frame |

Settings are saved per character. The blacklist itself is shared by all characters on the same realm.

A keybinding to open the window is under **Key Bindings → Blacklist Reborn**.

---

## Installation

1. Copy the `blacklist-reborn` folder into `World of Warcraft/Interface/AddOns/`.
   The folder must be named exactly `blacklist-reborn`, or WoW will not load it.
2. If you had the original **Black List** addon installed, **delete its `BlackList` folder**. The two can't run at the same time.
3. Start the game and make sure **Blacklist Reborn** is enabled on the character select screen.

No libraries or other addons are required.

### Keeping your list from the original Black List addon
Saved data is compatible, but WoW stores it under the addon's folder name. With the game **closed**, rename these files:

| From | To |
|---|---|
| `WTF/Account/<ACCOUNT>/SavedVariables/BlackList.lua` | `blacklist-reborn.lua` |
| `WTF/Account/<ACCOUNT>/<Realm>/<Character>/SavedVariables/BlackList.lua` | `blacklist-reborn.lua` |

Old entries are upgraded automatically the first time you log in.

---

## What changed from the original addon

- **Raids work.** Adding from raid frames and detecting blacklisted players in raids were both broken before.
- **No interface taint.** The original addon edited Blizzard's right-click menus directly. That made Blizzard hide *Target* (and *Main Tank* / *Main Assist*) and block *Set Focus* with an "addon blocked" error. Blacklist Reborn never modifies Blizzard's menus, Friends frame or popups.
- **No spam.** Mouseover, target, `/who` and guild roster warnings are gone. Invite and group-join notices each fire once.
- **No chat filtering.** The automatic "Ignored" whisper replies are gone.
- **Options now persist.** Before, they reset to their defaults on every login.
- **Removed:** guild auto-ban and auto-kick of inactive members.
- **New:** `/bl list`, `/bl warn` (with reasons), cross-realm entries, standalone window, per-player *Warn Me*.

---

## Compatibility

- **Client:** World of Warcraft 3.3.5a (Interface `30500`)
- **Locales:** built and tested on English clients. Other locales work, but class and race names in the edit panel are English.

---

## Credits

- **Original Black List addon:** Logan / ElrickEnonimis
- **Blacklist Reborn:** fiftybengt, with Claude Code
