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

    loadCities: function(component) {
        var action = component.get("c.getCityOptions");
        action.setCallback(this, function(resp) {
            if (resp.getState() === "SUCCESS") {
                component.set("v.cityOptions", resp.getReturnValue() || []);
            } else {
                component.set("v.errorMessage", this.extractError(resp));
            }
        });
        $A.enqueueAction(action);
    },

    loadSources: function(component) {
        var action = component.get("c.getSourceOptions");
        action.setCallback(this, function(resp) {
            if (resp.getState() === "SUCCESS") {
                component.set("v.sourceOptions", resp.getReturnValue() || []);
            } else {
                component.set("v.errorMessage", this.extractError(resp));
            }
        });
        $A.enqueueAction(action);
    },

    createLeadByCourse: function(component) {
        component.set("v.errorMessage", "");
        var course = component.get("v.course");
        var city = component.get("v.city");
        var source = component.get("v.source");
        var lastName = component.get("v.lastName");
        var phone = component.get("v.phone");
        var countryCode = component.get("v.countryCode");
        var email = component.get("v.email");

        if (!course || !city || !source || !lastName || !phone || !email) {
            component.set("v.errorMessage", "Course, City, Source, Last Name, Phone, and Email are required.");
            return;
        }

        var phoneValue = String(phone || "").trim();
        var phoneRegex = /^\d+$/;
        if (!phoneRegex.test(phoneValue)) {
            component.set("v.errorMessage", "Phone must contain only digits.");
            return;
        }

        if (countryCode === "+91" && phoneValue.length !== 10) {
            component.set("v.errorMessage", "If country code is +91, phone must be exactly 10 digits.");
            return;
        }

        if (countryCode !== "+91" && phoneValue.length > 13) {
            component.set("v.errorMessage", "If other country code, phone can be maximum 13 digits.");
            return;
        }

        component.set("v.isLoading", true);
        var action = component.get("c.createLeadByCourse");
        action.setParams({
            course: course,
            city: city,
            firstName: component.get("v.firstName"),
            lastName: lastName,
            countryCode: countryCode,
            phone: phoneValue,
            email: email,
            source: source
        });
        action.setCallback(this, function(resp) {
            if (resp.getState() === "SUCCESS") {
                var result = resp.getReturnValue();
                if (result && result.success && result.leadId) {
                    this.sendLeadToMiles(component, result.leadId);
                } else {
                    component.set("v.isLoading", false);
                    component.set("v.errorMessage", (result && result.message) ? result.message : "Failed to create Lead.");
                }
            } else {
                component.set("v.isLoading", false);
                component.set("v.errorMessage", this.extractError(resp));
            }
        });
        $A.enqueueAction(action);
    },

    sendLeadToMiles: function(component, leadId) {
        var action = component.get("c.sendLeadToMiles");
        action.setParams({
            leadId: leadId
        });
        action.setCallback(this, function() {
            component.set("v.isLoading", true);
            var navEvt = $A.get("e.force:navigateToSObject");
            if (navEvt) {
                navEvt.setParams({ recordId: leadId });
                navEvt.fire();
            }
            var closeEvt = $A.get("e.force:closeQuickAction");
            if (closeEvt) {
                closeEvt.fire();
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
