/*
    Author       : ROHIT SINGH BISHT
    Description  : 
*/
public abstract class BaseTriggerHandler implements ITriggerHandler {

    protected List<SObject> newList;
    protected List<SObject> oldList;
    protected Map<Id, SObject> newMap;
    protected Map<Id, SObject> oldMap;

    public BaseTriggerHandler(List<SObject> newList,List<SObject> oldList,Map<Id, SObject> newMap,Map<Id, SObject> oldMap) {
        this.newList = newList != null ? newList : new List<SObject>();
        this.oldList = oldList != null ? oldList : new List<SObject>();
        this.newMap  = newMap  != null ? newMap  : new Map<Id, SObject>();
        this.oldMap  = oldMap  != null ? oldMap  : new Map<Id, SObject>();
    }

    public virtual void beforeInsert() {}
    public virtual void beforeUpdate() {}
    public virtual void beforeDelete() {}
    public virtual void afterInsert() {}
    public virtual void afterUpdate() {}
    public virtual void afterDelete() {}
    public virtual void afterUndelete() {}
}