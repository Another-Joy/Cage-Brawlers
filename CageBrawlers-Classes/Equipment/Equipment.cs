using System.Collections.Generic;
using CageBrawlers.Modifiers;
using UnityEngine.TextCore.Text;

namespace CageBrawlers.Equipments
{
    public abstract class Equipment
    {
        public string Name { get; }
        public int Weight { get; }
        public List<Modifier> Modifiers { get; }

        protected Equipment(string name, int weight)
        {
            Name = name;
            Weight = weight;
        }

        public void UpdateEquipment(Character equippedBy){}
        
        
    }
}