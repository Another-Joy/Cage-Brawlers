using System.Collections.Generic;
using CageBrawlers.Damage;
using CageBrawlers.Modifiers;
using JetBrains.Annotations;
using UnityEngine.TextCore.Text;
using UnityEngine.UIElements;

namespace CageBrawlers.Equipments
{
    public class Weapon : HandEquipment
    {
        public WeaponType Type { get; }
        public DamageType DamageType { get; }
        public Dice Dice { get; }
        public int Range { get; }
        public List<WeaponTrait> Traits { get; }
        public Character EquippedBy { get; }
        
        
        
        public Weapon(string name, int weight, WeaponType type, DamageType damageType, Dice dice, int range,
            List<WeaponTrait> traits, Character equippedBy, [CanBeNull] List<Modifier> modifiers) : base(name, weight,
            modifiers)
        {
            Type = type;
            DamageType = damageType;
            Dice = dice;
            Range = range;
            Traits = traits;
            EquippedBy = equippedBy;
        }

        public DamageInfo Use() //Builds an initial DamageInfo for use later
        {
            return new DamageInfo(Dice, 0, 0, DamageType, 0);
        }
        
        
    }
}