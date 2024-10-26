document.addEventListener('DOMContentLoaded', () => {
    async function loadTimelineData() {
        try {
            const timeSelectValue = document.getElementById('timeSelect').value;
            let logsLimitValue = document.getElementById('logsLimit').value;
            logsLimitValue = /^[0-9]+$/.test(logsLimitValue) ? parseInt(logsLimitValue, 10) : null;
            const response = await fetch('/timeline_data', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json'},
                body: JSON.stringify({ since: timeSelectValue, limit: logsLimitValue}),
            });

            const data = await response.json(); // Parse JSON data

            const groups = new vis.DataSet(data.groups.map(group => ({
                id: group.id, // Unique ID for each group (service or container)
                content: group.name, // Display name for the group
                nestedGroups: group.containers || [], // Use nested groups for containers under services
                className: group.type === 'service' ? 'service-group' : 'container-group' // Add classes for styling
            })));
            const items = new vis.DataSet(data.items.map(item => {
                // Set 'group' to the container or service it belongs to
                return {
                    ...item,
                    group: item.groupId, // Associate item with a group ID (container or service)
                    start: new Date(item.start * 1000),
                    end: item.type === 'range' ? new Date(item.end * 1000) : null,
                    type: item.type === 'point' ? 'point' : 'range',
                    title: `Event Details: ${item.content}`,
                    className: item.type === 'point' ? 'event-point' : 'container-event'
                };
            }));
            // Specify options for the timeline
            const options = {
                stack: false, // Prevent stacking to keep items aligned with groups
                orientation: 'top',
                order: (a, b) => a.start - b.start,
                start: new Date(new Date().setHours(0, 0, 0, 0)),
                end: new Date(1000 * 60 * 60 * 24 + new Date().valueOf()),
                editable: false,
                margin: { item: 10, axis: 5 }
            };

            // Create the timeline
            const container = document.getElementById("visualization");
            if (container) container.innerHTML = '';
            const timeline = new vis.Timeline(container, items, groups, options);
            window.addEventListener("resize", () => timeline.redraw());
            // timeline.on('select', function (properties) { /* IN DEVELOPMENT: GETTING CONTAINERLOGS FUNCTION */
            //     const selectedItemId = properties.items[0]; // Get the ID of the selected item
            //     if (selectedItemId) {
            //         const selectedItem = items.get(selectedItemId); // Get the selected item details
            //
            //         // Check if the item has the backend_path field
            //         if (selectedItem.backend_path) {
            //             const url = `/get-container-logs/${selectedItem.id}`;
            //             window.location.href = url; // Redirect the browser to the generated URL
            //         }
            //     }
            // });
        } catch (error) {
            console.error("Error loading timeline data:", error);
        }
    }
    // Your existing code here
    const timeSelect = document.getElementById('timeSelect');
    timeSelect.addEventListener('change', () => {
        const selectedTimePeriod = timeSelect.value; // <-- Fix 'this.value' by using 'timeSelect.value'
    });

    const refreshButton = document.getElementById('refreshButton');
    refreshButton.addEventListener('click', () => {
        loadTimelineData();
    });
    loadTimelineData();
});


