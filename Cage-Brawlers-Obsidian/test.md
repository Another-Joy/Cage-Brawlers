Given the ideas at /Cage-Brawlers-Obsidian, all of them should be possible to implement. 
You may notice some of the equipments have skills. These are provided to the user.

Create a md guide on how to create these sorts of items with skills of their own, and move that and other guides to a /guides.

## Some explanations:

Opportunity Attacks
When a character moves to outside of the tiles adjacent to a Melee character, the latter makes an Opportunity attack: an automated attack. 

Surprise attacks are attacks that, given attacker A and defender D:
- D cannot see A, or
- D could not see A at the beginning of A's turn in case of a Melee Surprise attack.

Slowed is a Status Effect that reduces a characters movement by that percentage, rounded to the nearest int (for slowed by 33%: 3 movement becomes 2, 4 becomes 3 and 5 becomes 3)

Abilites can have Damage Modifiers if they dont have explicit damage. These modifiers are applied to the weapon's damage to get the final number and types of dice. The modifiers are also applied to any skills and effects that increase the attack's damage that use dice (and that give their bonuses to the attack directly. if a skill makes the character make an extra attack, those modifiers are not applied since the modifier are to be applied to the ability, not the attack produced by the skill). These modifiers are worded as XdY, where X changes the number of dice (to a minimum of 1) and Y changes the dice tier (2 > 4 > 6 > 8 > 10 > 12 > 16 > 20, a -1 dice tier jumps, for example, a 6 to a 4, not to a 5)

Abilities can have (or create attacks with) changed stats like accuracy and reliability. 

Cooldowns tick down at the end of turn, if applicable. A "2 turn" cooldown means when the skill is used, it cannot be used the next turn, and can be used again after. 3 turn cooldown increase the periode whre the skill cannot be used to 2 turns, and so on.

Weapons have a Weapon Type (as well as a Damage Type) that especifies what type of weapon they are. this is used for the Weapon Categories field of Classes and the requirements of abilities and skills. This should be an Enum

Dice Value can have incorporated Reliability. This is used for some weapons (non for now) and for classes' hit dice.

Classes can have more than one Primary and more than one Secondary Stat

## Keywords:
Versatile: Can be Equiped as One or Two-handed. This is detected automaticaly if there is another equipemnt on the off-hand. While equiped as Two-Handed, the weapon has the damage of the keywords, between parenthesis

Finesse: 
Finesse Weapons use Wis for Damage bonus instead of Str, have a double accuraacy bonus from Dex, and gain reliability from Dex (at the same rate of normal accuracy bonus)

Light:
This weapon can be used in the off-hand. While using two weapons this way, when attacking, each weapon makes one attack (all skills trigger once for each attack).

Magazine:
This weapon has a magazine for ammo. Magazine weapons can be fully reloaded as a Beginning Phase action. Attacking consumes 1 Ammo, and attacks cannot be made without ammo. Weapons start with magazines completly filled, and that ammo does not count towards the weight or ammo capacity. Magazine weapons must display their ammo to the user, but not to the opponent

Aiming:
This weapon can only be fired when the equipped character does not move during their Beginning Phase. They ignore the accuracy fall-off of ranged attacks.

Inacurate:
The weapon's accuracy fall-off is doubld.




After all this, implement some of the items provided (not all are needed)


