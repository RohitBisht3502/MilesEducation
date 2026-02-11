({
    startFlow: function(component) {
        var flow = component.find("leadFlow");
        if (flow) {
            flow.startFlow("Lead_New_Override_Flow");
        }
    }
})
