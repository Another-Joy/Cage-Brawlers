# General Idea
Cage Brawlers is a PvP team and turn-based tactics game. Using a combat system similar to DnD, characters are built and equipped to fight each other.

# Concepts

## Characters
Each character is built and controlled by a player, with multiple customization options from class, stats, equipments, and skills.

Characters can be permanently killed on some matches, and should be considered disposable by players

Characters have a defined Level, and can level up by playing. When Leveling, Stats can be increased and skills can be learnt

### Stats
Each character has 5 main stats, with most other stats derived from them.
#### Strength
Measures the raw strength and power of a character
Affects:
- Physical Attack Damage
- Carry Weight

#### Dexterity
Measures the speed and agility of a character
Affects:
- Physical Attack Accuracy
- Movement Speed
- Evasion
- Initiative

#### Constitution
Measures a characters capacity to resist wounds, and to stay fighting in spite of them
Affects:
- Health

#### Wisdom
Measures a character's intuition, common sense, connection to the world, capactity to interpret it
Affects:
- Ranged Attack Damage
- Magical Attack Damage (class dependent)
- Magical Ability Modifier (class dependent)
- Healing Amount

#### Inteligence
Measure a character hard knowledge of various themes and general mental acuity.
Affects:
- Ranged Attack Accuracy
- Magical Attack Damage (class dependent)
- Magical Ability Modifier (class dependent)
- Healing Amount

## Equipments

Equipments can be of varous types: Hand (Weapons, Shields, Buffs), Armor and Support (Bullets, Bolts, Arrows, Potions)
All Equipment has weight to it. If the sum of the equipments weight is greater than the Chars carry capacity, they becom overcumbered losing 1 Movement and 1 extra for every 3 kg above the limit
Equipments have not only inherent atributes (such as an armors Armor Value, or a weapons Damage) but also conditional abilities (e.g. an axe that deals double damage against heavy armor, but only if damaging armor) and keywords (that affect the weapons funcionality in varous ways).

### Hand Equipments

Hand equipments can fit into one or both hand slots, depending on their type and keywords.
Any equipment that can go into off-hand can go into main-hand, but not vice versa.
Shields and Buffs are off-hand items, while Weapons are main-hand only.

#### Weapons
Weapons have a Damage Type (or Supertype) and a Weapon Type (or Subtype)
Damage Types are: Physical, Ranged, Magical
Weapon Types are what the weapon itself is, like and axe, sword, bow, etc.
Each weapon has a base Damage (in Dice), Range if applicable and Keywords if applicable

#### Shields
Shield have a evasion bonus and a possible movement change

#### Buffs
Buff items can increase various stats, provide conditional buffs or otherwise aid during the battle.

### Armor

There are 3 types of Armor: Heavy, Medium and Light
Heavy Armor is fully made of metal and is very heavy, but very durable and protective. Reducing the Character Evasion and Movement to grant high Armor Value, but low or no pockets.
Medium Armor is usually made of leather or hide, or metal that cover only the most vital parts. Providing some protection and pockets while not reducing mobility too much.
Light Armors are made of cloth, and provide increased mobility, evasion and pockets while giving little to no Armor Value.

All armor occupies a single slot in the Characters equipment, and it opens slots for potions, bolts, bullets and arrows depending on it.

### Support

A variable "equipment" that can also be named consumables. From arrows, bolts, bullets and potion, the amount a character can carry is derectly dependent on the armor they're wearing.

## Skills
Skills are learn by Chars no skill trees during Leveling. They can grant passive abilities, effects, useful combat abilities or other perks.

### Skill Trees
Each Char has 3 skill trees: 1 for their class and 1 for useful abilities based on their highest stat and 1 for a random weapon associated with their class.

Skill tree are randomly ordered, but since each skill is assigned a level value, their have similar structure between generations.


## Combat

Combat is the main part of the game, involving a turn structure and virtual dice rolling

### Turns
A game is divided into rounds, where each charaacter acts once (usually) 

At the begginign of a battle, each character rolls for initiative. THis defines the tunr order. If two plaers have the same initiative, they then roll again, with the highest roll gaining +1 to their initative. If this causes another conflict, repeat until there are no initiative conflicts.

During each turn, a character has 3 actions: Beginning, Main and Ending Actions. These are slot form abilites (inherent such as movement or normal attack, or especial abilities from skills). All of these have a dedicated Phase (movement is for beginnign, Attack is for Main for ex)

### Dice
Most Weapons (and Buffs), Attacks, and Abilities have their values as Dices. These Dices are rolled to determine final damage and values. Reliabilty is a vlaue that can affect hese rolls, with a formula. (implement inside the roll function for dices that it needs a reliability)
Multiple dice can be rolled or bundled together (ex: a weapon that uses 2d6 as damage)

### Attacks
Attacks can be made by Characters to other characters in range (which by default is the equipped we.  Abilities may change the range an attack can be made. 
Attacks are rolled individually for weapons or abilities that make more than 1 attack. If a character has 2 weapons equipped (one in main hand and one in off-hand) that character makes two attacks, one with each weapon)

### Evasion
Evasion is split into 2 part: Character Evasion and Equipment Evasion. 
Character evasion is given by a chars Dex and can be affected by Equipments (like armor).
Equipment evasion is from shields and other buffs.
These are then sumed (if either of those is below 0, consider that value as 0) and used as the defenders Evasion stat, taht is then compared to the attack's accuracy.

### Health Bars
Each character has their health bars split into 3 segments.
These segments can have different sizes depending on the characters class. The size is a percentage of the total health, not an absolute.
When a character is Knocked down (due to loss of all hp), its right-most, non-disabled segment is disabled for the rest of the combat. This effectivly reduced the chars max health. If a character has all their segments disabled, it dies and is lost forever (equipments are lost) 




