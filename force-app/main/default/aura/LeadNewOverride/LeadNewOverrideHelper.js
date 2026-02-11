({
    loadRecordTypes: function(component) {
        component.set("v.isLoading", true);
        var action = component.get("c.getLeadRecordTypes");
        action.setCallback(this, function(resp) {
            component.set("v.isLoading", false);
            if (resp.getState() === "SUCCESS") {
                component.set("v.recordTypes", resp.getReturnValue());
            } else {
                component.set("v.errorMessage", this.extractError(resp));
            }
        });
        $A.enqueueAction(action);
    },

    createLead: function(component) {
        component.set("v.errorMessage", "");
        var lastName = component.get("v.lastName");
        var phone = component.get("v.phone");
        var email = component.get("v.email");
        var recordTypeId = component.get("v.recordTypeId");

        if (!recordTypeId || !lastName || !phone || !email) {
            component.set("v.errorMessage", "Last Name, Phone, and Email are required.");
            return;
        }

        component.set("v.isLoading", true);
        var action = component.get("c.createLead");
        action.setParams({
            recordTypeId: recordTypeId,
            firstName: component.get("v.firstName"),
            lastName: lastName,
            phone: phone,
            email: email
        });
        action.setCallback(this, function(resp) {
            component.set("v.isLoading", false);
            if (resp.getState() === "SUCCESS") {
                var result = resp.getReturnValue();
                if (result && result.success && result.leadId) {
                    var navEvt = $A.get("e.force:navigateToSObject");
                    if (navEvt) {
                        navEvt.setParams({ recordId: result.leadId });
                        navEvt.fire();
                    }
                    var closeEvt = $A.get("e.force:closeQuickAction");
                    if (closeEvt) {
                        closeEvt.fire();
                    }
                } else {
                    component.set("v.errorMessage", (result && result.message) ? result.message : "Failed to create Lead.");
                }
            } else {
                component.set("v.errorMessage", this.extractError(resp));
            }
        });
        $A.enqueueAction(action);
    },

    extractError: function(resp) {
        var errors = resp.getError();
        if (errors && errors.length > 0) {
            if (errors[0].message) return errors[0].message;
            if (errors[0].pageErrors && errors[0].pageErrors.length > 0) {
                return errors[0].pageErrors[0].message;
            }
        }
        return "Unexpected error.";
    }
})
