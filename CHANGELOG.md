# RAID-SuperBLT Basemod Changelog

This lists the changes between different versions of the RAID-SuperBLT basemod,
the changes for the DLL are listed in their own changelog.
Contributors other than maintainers are listed in parenthesis after specific changes.

## 2.0.3
- updated chinese translation by FR0Z3_N3.Borealis and Schordinger_Sig

## v2.0.1

- updated spanish translation by ErnestJugend
- updated russian translation by Punished Bernadetta
- translate status text on modsgui

## v2.0.0

- entirely rewritten mods/downloads manager pages (and notifications panel) to fit the RAID theme much better, (based on RaidGuiBase).
- implemented controller/keyboard support to same pages (not to notifications gui in main menu though, use the entries in options instead)
- dropped pd2-themed custom icons in favor of new ones by dribbleondo and shinrax2
- dropped BLTCustomComponent and other old PD2 based GUI controls
- added `BLTMenu:AutoBindNamedControlsBegin()` and `BLTMenu:AutoBindNamedControlsEnd()` for auto routing `on_menu_move` param when building custom option menus (pass `no_auto_bind = true` to single controls, to skip)
- added `auto_select_on_hover = true` param to BLTMenu controls. (defaults to false for backwards compat) - this also makes sure descriptions are shown, when using kb/controller
- improved handling of ui updates when download states change in BLTUpdate and DownloadManager
- unified yes/no button-order in dialogs with the game
- several internal fixes and cleanups
- re-enabled use of blt.asset_db (which is now fixed in dll)

## v1.3.0

- new mod options sub menu, matching the style of main menu and options.
  - deprecated `inject_menu = "blt_options"`. use `inject_list` instead.
  - `blt_options` injects can now handle the `icon` param, which can be any regular gui tweak icon.
- injected lists can now automatically be sorted, if `blt_can_sort_list` is passed, and no injection injects by `point`.
  - ..which now applies to the new `blt_options` list.
- reworked MenuComponent creation, so that keyboard interactions should now be somewhat possible to implement in BLTMenus. (might require some more work to be fully usable, see MenuHelper changes)
- other menu fixes:
  - using the keyboard now works in mod options list and should not crash the game any longer.
  - using internal raid_menu helper functions where possible.
  - fixed special_btn_released when chat is focused.
  - BLTMenu: fixed option description screen alignment and made font and color more raid-like.

## v1.2.10

- added custom MultiChoice/stepper menu controls with icons instead of texts. (put icon_id or texture & texture_rect, instead of text or text_id in params.options)
new factory functions:
  - BLTMenu:MultiChoiceIcons(params)
  - RaidGUIPanel:stepper_icons(params)
  - RaidGUIPanel:stepper_icons_simple(params) [used internally for the stepper itself (without label)]

## v1.2.9

- fixed LuaNetworking events ChatManagerOnReceiveMessage and NetworkReceivedData.

## v1.2.8

- generalized BLT:make_fine_text and BLT:make_fine_text_aligning, as MenuNodeBaseGui.make_fine_text is now gone in U25.1

## v1.2.7

- dependency-system fixes by 11BelowStudio

## v1.2.6

- fixed crash when clicking the download button of a blt mod, due to a deleted pd2 color in u25

## v1.2.5

- no changes

## v1.2.4

- no changes

## v1.2.3

- added support for id="" in update tags (not just 'identifier')

## v1.2.2

- fixed min_sblt_version check
- fixed saving blt options when leaving the mods menu

## v1.2.1

- fixed U24 menu animations in options
- added U24 menu icon support
- fixed crash when setting keybinds with U24
- added `Utils.GetFontBySize()` to help mods with scaling fonts
- added new icon for SBLT by [Dribbleondo](https://www.youtube.com/channel/UCD_C63csNn6SDm9IirZN3oA)
- improved reloading game logic in BLTDownloadManagerGui. it now only shows the button to reload if no mod using the `assets` module

## v1.2.0

- added BLT.fonts table, reflecting pd2 font presets
- added open contact button
- added Util.OpenUrl and Util.OpenUrlSafe (with yes no msgbox)
- added reload button to BLTDownloadManagerGui if developer.txt is present
- added min_sblt_version for supermod.xml
- fixed crashes in main menu due to missing event handlers when using arrow keys or enter
- fixed always applying default localization
- fixed QuickMenu cancel button flag for raid

## v1.1.0

- fixed auto updater download validation for pure-xml mods (as in v1.0.1)
- fixed menu ui updates
- improved menu visuals (no blend_mode "add" in panels and texts)
- deprecated MenuManager:register_menu_new (use RaidMenuHelper:RegisterMenu instead)

## v1.0.3

- fixed RaidMenuHelper:CreateMenu() when BeardLib is not installed (implemented table.merge)

## v1.0.2

- fixed keybinds menu
- fixed dependencies system

## v1.0.1

- equalized features of mod and supermod, and got rid of own mod.txt

## v1.0.0

- based on PD2-SuperBLT v1.4.0
- tons of patches and fixes for RAID
- ported raid specific features from RaidBLT
- removed linux/w32/pd2/vr codes
- added modworkshop provider for auto updates
