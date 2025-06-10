using System.Collections.Generic;

namespace CageBrawlers.Modifiers
{
    public abstract class Modifier
    {
        public ModifierDuration Duration { get; }
        public int DurationInt { get; }
        public List<ModifierCondition> Conditions { get; }


        public Modifier(ModifierDuration duration, int durationInt, ModifierCondition condition) : this(duration,
            durationInt, new List<ModifierCondition> { condition }){}
        public Modifier(ModifierDuration duration, int durationInt, List<ModifierCondition> conditions)
        {
            Duration = duration;
            DurationInt = durationInt;
            Conditions = conditions;
        }
        
        public abstract ModifierStatsAccumulator getModifierStats();
    }
}