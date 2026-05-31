Saving Stats, skills and abilities still does not work, they are simply reverted to the original.

selecting the way a character faces after moving has north and south switched, as well as northeast and southeast, and northwest and southwest.

The attack resolver will need to be heavily rewritten. 
First, each attack is a bundle of dices (possibly different), not a single type of dice. These extra DiceValues can come from various sources, and act as a sum or reduction to the attack's damage.
Each of these DiceValues can have their own reliability, but there is also a general reliability that applies to all DiceValues in an attack. Sum them if tehre is a general and a specific (easy to implement, since if there is no specific it defaults to 0).
All these DiceValues are part of the same attack, so they do not hit or miss individually, but do so as a group.
Currently, skills like Crypt Candle have no use since their bonuses are never triggered or added. Fix that. this is one of the reasons why having Multiple DiceValues is important: a Mage attacking with a Tome uses 1d8 from the Tome, + 1d4 fro the Candle, increasing the damage greatly. Note that the stat bonus is only applied once (but leave this as a multipliers, so a skill that increases the stat bonus' effect can eventually exist)

The health states should be:
Unscathed - No health damage
Bruised - First segment damaged
Bloodied - First segment depleted
Heavily Bloodied - Second segment depleted
Downed - No Health


You are allowed to make breaking changes. Patch up any errors from the interactions between the updated AttackResolver and other parts, prioritising the new AttackResolver Implementation
