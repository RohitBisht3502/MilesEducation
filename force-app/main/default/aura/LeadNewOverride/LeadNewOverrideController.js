({
    doInit: function(component, event, helper) {
        helper.loadCourses(component);
    },

    handleInputChange: function(component, event, helper) {
        var name = event.getSource().get("v.name");
        var value = event.getSource().get("v.value");
        if (name === "course") component.set("v.course", value);
        if (name === "firstName") component.set("v.firstName", value);
        if (name === "lastName") component.set("v.lastName", value);
        if (name === "phone") component.set("v.phone", value);
        if (name === "email") component.set("v.email", value);
    },

    handleCreate: function(component, event, helper) {
        helper.createLeadByCourse(component);
    },

    handleCancel: function(component, event, helper) {
        helper.handleCancel(component);
    }
})
