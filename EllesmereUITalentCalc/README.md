# EllesmereUI Talent Calculator

A talent calculator for **WoW Forever**, built as a module of **EllesmereUI**.
Plan a talent build for any class, click the talents in the order you want to learn
them, and your class's build is **learned automatically every time you level up**.

Version **9.4** · Author: **Dworak**

---

## Requirements

| What | Why |
|---|---|
| **WoW Forever** client (Interface `16001`) | The calculator is made for Forever's talent trees: the three classic trees per class, the classic tier rule, the 51-point cap and the Progress Legacy talent passive. |
| **EllesmereUI** 9.4 or newer (the `EllesmereUI` and `EllesmereUIOptions` folders) | The calculator is a page inside the EllesmereUI options panel and uses its widgets, fonts and colors. It needs an EllesmereUI version with the Plugin API (`EllesmereUI\PLUGINS_API.md`). Get EllesmereUI from its own download source. |
| **EllesmereUIDworak** | Creates the **Dworak** section in the EllesmereUI sidebar that the calculator lives in. Without it the calculator does not load. |

Nothing else is needed. The other Dworak modules (Bag Slots, Talents reminder) are optional.

## Installation

1. Close the game (or be ready to `/reload`).
2. Copy these two folders into `World of Warcraft\_classic_beta_\Interface\AddOns\`
   (use your own Forever client folder if it is named differently):

   ```
   EllesmereUIDworak\
     EllesmereUIDworak.toc
     EllesmereUIDworak.lua
   EllesmereUITalentCalc\
     EllesmereUITalentCalc.toc
     EllesmereUITalentCalc_Core.lua
     EllesmereUITalentCalc_Page.lua
     README.md
   ```

3. Start the game and make sure **EllesmereUI**, **EllesmereUI Dworak** and
   **EllesmereUI Talent Calculator** are enabled in the AddOns list.
4. Open it: EllesmereUI panel → **Dworak** → **Talent Calculator**, or type `/tcalc`.

## How to use it

### Plan a build
1. Pick a class in the **Class** dropdown. Each class has its own build.
2. Click the talents **in the order you want to learn them**:
   - **Left-click**: add a rank
   - **Right-click**: remove one rank
   - **Shift + right-click**: remove every rank of that talent
3. The **Learning Order** list under the trees shows every point of the build with
   the level you get it at (`lvl 10  Deadly Aspects 1/5` ...).

The calculator follows the game's rules, so a talent you cannot take yet is greyed out.
Its tooltip says why ("Requires 10 points spent in this tree", "Requires ... at max rank").

- **Tier rule:** row *N* of a tree needs *(N − 1) × 5* points spent **in that tree**.
- **Arrows:** a talent behind an arrow needs the talent before it at max rank.
- **Points:** at most **51** talent points.
- **When you remove a point**, any later talent that no longer meets its requirement
  drops out of the build automatically.

### Learn automatically on level up
With **Learn Automatically on Level Up** on (the default), every level-up spends your new
talent point on the next talent of your class's build and applies it, the same as pressing
*Apply Changes* in the talent window. The chat tells you what was learned.

- **In combat:** it waits and learns the talents when combat ends.
- **Unapplied changes:** if the game's talent window has changes you have not applied yet,
  it leaves them alone and tells you.
- **Learn Now:** spends any free points right away, without waiting for a level-up.
- **Copy Current:** starts the build with the talents your character already has, so you
  only plan the rest.

### Progress Legacy points
The **Adventure** branch of the Progress Legacy tree has a talent passive. Each point in it
moves your first talent point one level earlier (5 points: level 5 instead of level 10).
You still never get more than 51 talent points. The calculator reads this from your
character, and the levels in the Learning Order use it. The **Legacy Talent Points** row
shows what it found, for example `5 / 5   first talent point at level 5   max 51 points`.

The big line on top shows your character's **Unspent talent points**.

### Saved builds
Every class keeps its own list of saved builds. A Priest build never shows up for a Hunter.

- **Save Build**: save the current build under a name. Saving under an existing name overwrites it.
- **Saved Build** (dropdown): open a saved build. It becomes the build you edit and learn.
- **Delete Build**: select a build in the dropdown, then press Delete Build.
- **Clear**: empties the calculator. Saved builds are not touched.

### Share builds
- **Export**: shows the build as a short text, already selected. Copy it with **Ctrl+C**
  and send it to anyone, for example:

  `EUITC1:ROGUE:Combat leveling:105741x2.105708x3.105737x3`

- **Import**: paste a text with **Ctrl+V**. The calculator switches to that class, opens the
  build and saves it under its name (or "Name (2)" if you already have one with that name).

The text holds the class, the name and the full learning order, so the other player gets
the build exactly as you planned it.

## Slash commands

| Command | What it does |
|---|---|
| `/tcalc` or `/talentcalc` | Opens the calculator |
| `/tcalc learn` | Learns the next talents of your build now (same as **Learn Now**) |
| `/tcalc debug` | Prints what the game reports: talent tree, points, first talent level, Legacy points, saved trees. Useful for bug reports. |

## How it works

- **Talent data:** read from the game itself (the same trait tree the Forever talent window
  uses), so new or changed talents show up without an addon update.
- **Your own class:** always read live.
- **Other classes:** read through the game's view mode where the client allows it. Otherwise
  the calculator uses the tree it saved the last time a character of that class logged in.
  If a class shows "No talent data yet", log in once with a character of that class.
- **Clean-up:** the client lists a few talents twice or outside the grid. The calculator
  hides those, so the trees match the in-game talent window.
- **Colors:** everything follows **Global Settings → UI Accent Color** of EllesmereUI.

### Saved data
| Saved variable | Scope | Contents |
|---|---|---|
| `EllesmereUITalentCalcDB` | Account | Saved trees per class, the current build and saved builds per class |
| `EllesmereUITalentCalcCharDB` | Character | Auto-learn on/off, the class you last viewed, your first talent level |

To reset everything, delete these from your `WTF` folder while the game is closed.

## Troubleshooting

- **The calculator is not in the EllesmereUI panel:** check that **EllesmereUIDworak** is
  installed and enabled, and that your EllesmereUI version has plugin support.
- **"No talent data for <class> yet":** log in once with a character of that class.
- **A talent was not learned on level up:** the chat says which talent and why. Usually the
  build order asks for a talent whose requirements your character does not meet yet (for
  example, you spent points differently by hand). Fix the order, or press **Learn Now**.
- **Levels in the Learning Order look wrong:** run `/tcalc debug` and check the first talent
  level and Legacy points it reports.
- **Reporting a bug:** include a screenshot and the `/tcalc debug` output.
