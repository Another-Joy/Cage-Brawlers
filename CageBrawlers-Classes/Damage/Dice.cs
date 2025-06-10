using System;

namespace CageBrawlers.Damage
{
public class Dice
    {
        private int _diceCount;
        private int _diceSides;


        public Dice(int diceCount, int diceSides)
        {
            _diceCount = diceCount;
            _diceSides = diceSides;
        }


        public int MaxRoll()
        {
            return _diceCount * _diceSides;
        }
        public int MinRoll()
        {
            return _diceCount;
        }


        public int Roll()
        {
            int total = 0;
            for (int i = 0; i < _diceCount; i++)
            {
                total += UnityEngine.Random.Range(1, _diceSides + 1);
            }
            return total;
        }

        public int Roll(int bonus, int reliability = 0)
        {

            if (reliability >= 200)
            {
                return MaxRoll() + bonus + Roll(bonus, reliability - 200);
            }
            else if (reliability > 100)
            {
                return MaxRoll() + Roll(bonus, reliability - 200);

            }
            else if (reliability > 0)
            {
                return RoundUp((Roll()*(100-reliability)/100) + reliability * MaxRoll() / 100) + bonus;
            }
            else if (reliability == 0)
            {
                return Roll() + bonus;
            }
            else if (reliability >= -100)
            {
                return RoundUp((Roll()*(100+reliability)/100) - reliability * MinRoll() / 100) + bonus;
            }           
            else if (reliability >= -200)
            {
                reliability = (-reliability) -100;
                return Math.Max(bonus - RoundUp((Roll()*(100-reliability)/100) + reliability * MaxRoll() / 100), 0);
            }
            else
            {
                return 0;
            }

        }

        public int RoundUp(int value)
        {
            return (int)Math.Round((double)value, MidpointRounding.AwayFromZero);
        }


        public static Dice operator +(Dice a, Dice b)
        {
            if (a._diceSides != b._diceSides)
            {
                throw new System.Exception("Cannot add dice with different sides");
            }
            return new Dice(a._diceCount + b._diceCount, a._diceSides);
        }


    }
}