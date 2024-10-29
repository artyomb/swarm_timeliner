document.addEventListener('DOMContentLoaded', () => {
    async function loadTimelineData(backend_path='/timeline_data') {
        try {
            const timeSelectValue = document.getElementById('timeSelect').value;
            let logsLimitValue = document.getElementById('logsLimit').value;
            logsLimitValue = /^[0-9]+$/.test(logsLimitValue) ? parseInt(logsLimitValue, 10) : null;
            console.log("Logs value is " + logsLimitValue.toString());
            const response = await fetch(backend_path, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json'},
                body: JSON.stringify({ since: timeSelectValue, limit: logsLimitValue}),
            });

            const data = await response.json(); // Parse JSON data

            const groups = new vis.DataSet(data.groups.map(group => {
                const title_for_group = group.type === 'service' ? `Group ${group.id} with containers: ${group.containers ? group.containers.join(', ') : 'none'}` : `Container with id = ${group.id}`;
                return {
                    id: group.id, // Unique ID for each group (service or container)
                    content: group.type === 'service' ? `Service ${group.id}` : 'Service container with events', // Display name for the group
                    nestedGroups: group.containers || null, // Use nested groups for containers under services
                    title: title_for_group, // Title for the group
                    className: group.type === 'service' ? 'service-group' : 'container-group' // Add classes for styling
                }
            }));
            const items = new vis.DataSet(data.items.map(item => {
                // Set 'group' to the container or service it belongs to
                const typeClass = item.type === 'point' ? 'event-point' : 'container-event';
                const statusClasses = Array.isArray(item.statuses) && item.statuses.length ? item.statuses.join(' ') : '';
                const className = `${typeClass} ${statusClasses}`.trim();
                return {
                    ...item,
                    content: item.content.length > 9 ? item.content.substring(0, 6) + '...' : item.content,
                    group: item.groupId, // Associate item with a group ID (container or service)
                    start: new Date(item.start * 1000),
                    end: item.type === 'range' ? new Date(item.end * 1000) : null,
                    type: item.type === 'point' ? 'point' : 'range',
                    title: `Item details: ${item.content} with id = ${item.id}`,
                    className: className,
                    backend_init: item.type === 'range' ? {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json'},
                        body: JSON.stringify({ cont_id: item.id}),
                    } : null
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
                margin: { item: 10, axis: 5 },
                showCurrentTime: false
            };

            // Create the timeline
            const container = document.getElementById("visualization");
            if (container) container.innerHTML = '';
            const timeline = new vis.Timeline(container, items, groups, options);
            window.addEventListener("resize", () => timeline.redraw());
            timeline.on('select', async function (properties) {
                const selectedItemId = properties.items[0];
                if (selectedItemId) {
                    const selectedItem = items.get(selectedItemId);
                    if (selectedItem.backend_init) {
                        const backend_path = '/get_cont_logs';
                        try {
                            const logs_response = await fetch(backend_path, selectedItem.backend_init);
                            if (!logs_response.ok) {
                                throw new Error(`Error: ${logs_response.statusText}`);
                            }
                            const logs_data = await logs_response.json();
                            const newTab = window.open('', '_blank');

                            // Write the JSON response to the new tab as formatted HTML
                            if (newTab) {
                                newTab.document.open();
                                const json_data = JSON.parse(logs_data);
                                newTab.document.write(`
                                    <html>
                                        <head>
                                            <title>Response Data</title>
                                            <style>
                                                body { font-family: Arial, sans-serif; padding: 20px; }
                                                pre { background: #f4f4f4; padding: 10px; border: 1px solid #ddd; }
                                            </style>
                                        </head>
                                        <body>
                                            <h1>Response Data</h1>
                                            <pre>${json_data.message}</pre>
                                        </body>
                                    </html>
                                `);
                                newTab.document.close();
                            } else {
                                alert("Popup blocker prevented opening a new tab.");
                            }
                        } catch (error) {
                            console.error("Error fetching data:", error);
                            alert("An error occurred while fetching data. Check the console for details.");
                        }
                    }
                }
            });
        } catch (error) {
            console.error("Error loading timeline data:", error);
        }
    }
    // Your existing code here
    const timeSelect = document.getElementById('timeSelect');
    timeSelect.addEventListener('change', () => {
        const selectedTimePeriod = timeSelect.value;
    });

    const refreshButton = document.getElementById('refreshButton');
    refreshButton.addEventListener('click', () => {
        loadTimelineData('/timeline_data');
    });
    const healthChecksButton = document.getElementById('healthChecksButton');
    healthChecksButton.addEventListener('click', () => {
        loadTimelineData('/get_health_checks');
    });
    loadTimelineData('/timeline_data');
});


