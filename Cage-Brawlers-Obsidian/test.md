Reckless assault, regenerate, hip shot and riposte are all rejecting. seems to be this error:
SCRIPT ERROR: Invalid call to function 'get_name' in base 'GDScript'. Expected 0 argument(s).
          at: WeaponData.get_weapon_type_name (res://scripts/data/WeaponData.gd:119)
          GDScript backtrace (most recent call first):
              [0] get_weapon_type_name (res://scripts/data/WeaponData.gd:119)
              [1] process_ability (res://scripts/combat/CombatManager.gd:488)
              [2] handle_action (res://scripts/server/ServerGame.gd:206)
              [3] rpc_submit_action (res://scripts/Main.gd:104)
    

Remake the Chars stats. 

Their total stats cannot exceed 60, and each stat must be between 8 and 16. Make them in accordance to what would be logical for their classes.

I need a way to see what tiles are actually movable to / which enemies can be attacked. All distances are calculated as manhattan distances.

The rogue had 100 hp in the test game, which is a bug. find it.

The HP bars still show percentage. Make them show actual ints, instead of having onyl a small int at the top. the int at the top can stay for totals. HP is distributed along segments by giving the left most segment priority (e.g: a char with 10 HP and segments 0.15, 0.25 0.60 will have segments HP as 2/3/5)

The context of the attack must also show reliability for dices

Note that acuracy bonuses form stats are +5% per ppoint. I have already fixed some of them (by putting a x5 on some)