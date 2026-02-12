({
    loadCourses: function(component) {
        component.set("v.isLoading", true);
        component.set("v.errorMessage", "");
        var action = component.get("c.getLeadCourses");
        action.setCallback(this, function(resp) {
            component.set("v.isLoading", false);
            if (resp.getState() === "SUCCESS") {
                component.set("v.courseOptions", resp.getReturnValue() || []);
            } else {
                component.set("v.errorMessage", this.extractError(resp));
            }
        });
        $A.enqueueAction(action);
    },

    createLeadByCourse: function(component) {
        component.set("v.errorMessage", "");
        var course = component.get("v.course");
        var lastName = component.get("v.lastName");
        var phone = component.get("v.phone");
        var email = component.get("v.email");

        if (!course || !lastName || !phone || !email) {
            component.set("v.errorMessage", "Course, Last Name, Phone, and Email are required.");
            return;
        }

        component.set("v.isLoading", true);
        var action = component.get("c.createLeadByCourse");
        action.setParams({
            course: course,
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

    handleCancel: function(component) {
        var navUrl = "/lightning/o/Lead__c/list?filterName=Recent";
        var navEvt = $A.get("e.force:navigateToURL");
        if (navEvt) {
            navEvt.setParams({ url: navUrl });
            navEvt.fire();
        }
        var closeEvt = $A.get("e.force:closeQuickAction");
        if (closeEvt) {
            closeEvt.fire();
        }
    },

    extractError: function(resp) {
        try {
            if (!resp || typeof resp.getError !== "function") {
                return "Unexpected error.";
            }
            var errors = resp.getError();
            if (errors && errors.length > 0) {
                if (errors[0].message) return errors[0].message;
                if (errors[0].pageErrors && errors[0].pageErrors.length > 0) {
                    return errors[0].pageErrors[0].message;
                }
            }
            return "Unexpected error.";
        } catch (e) {
            return "Unexpected error.";
        }
    }
})
