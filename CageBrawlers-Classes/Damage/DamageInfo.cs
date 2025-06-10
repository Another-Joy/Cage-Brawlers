using System.Collections.Generic;

namespace CageBrawlers.Damage
{
    public class DamageInfo
    {
        public List<Dice> Dice { get; }
        public int Bonus { get; }
        public int? Accuracy { get; }
        public DamageType Type { get; }
        public int Reliability { get; }

        public DamageInfo(Dice dice, int bonus, int? accuracy, DamageType type, int reliability = 0) : this(
            new List<Dice> { dice }, bonus, accuracy, type, reliability)
        {
        } //constructor for a single Die, calls second

        public DamageInfo(List<Dice> dice, int bonus, int? accuracy, DamageType type, int reliability)
        {
            Dice = dice;
            Bonus = bonus;
            Accuracy = accuracy;
            Type = type;
            Reliability = reliability;
        }


        public AttackResult CalculateDamage(int evasion = 0)
        {
            var total = 0;
            if (Accuracy.HasValue) // if damage has accuracy, it can miss or crit
            {
                var rng = UnityEngine.Random.Range(1, 101);

                if (evasion >= (rng + Accuracy)) return new AttackResult(0, true); // attack missed, 0 damage

                foreach (var dice in Dice) total = dice.Roll(Bonus, Reliability); //calculate damage

                return evasion < (rng + Accuracy - 100)
                    ? new AttackResult(total * 2, false, true)
                    : // critical hit, 2x damage
                    new AttackResult(total); //normal hit, 1x damage
            }

            // attack has no accuracy (such as a magic attack) and always hits for normal damage
            foreach (var dice in Dice) total = dice.Roll(Bonus, Reliability); //calculate damage
            return new AttackResult(total); //normal hit, 1x damage
        }
    }
}