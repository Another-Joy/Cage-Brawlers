namespace CageBrawlers.Modifiers
{
    public enum ModifierCondition
    {
        // timing
        OnTurnStart,
        OnTurnEnd,
        OnRoundStart,
        OnRoundEnd,
        OnCombatStart,
        
        //
        
        // attack attempted (before hit check)
        OnAttackDealt,
        OnAttackTaken,
        OnMeleeAttackDealt,
        OnMeleeAttackTaken,
        OnRangedAttackDealt,
        OnRangedAttackTaken,
        OnMagicAttackDealt,
        OnMagicAttackTaken,
        
        // damage confirmed (after hit check)
        OnEvade,
        OnMeleeEvade,
        OnRangedEvade,
        OnMagicEvade,
        OnDamageDealt,
        OnDamageTaken,
        OnMeleeDamageDealt,
        OnMeleeDamageTaken,
        OnRangedDamageDealt,
        OnRangedDamageTaken,
        OnMagicDamageDealt,
        OnMagicDamageTaken,
        
        //healing confirmed
        OnHealingDealt,
        OnHealingTaken,
    }
}