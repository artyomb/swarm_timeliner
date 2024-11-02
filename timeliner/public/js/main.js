function synchronizeDataset(source, target) {
    source.on('add', (event, properties) => {
        target.add(properties.items);
    });

    source.on('update', (event, properties) => {
        target.update(properties.items);
    });

    source.on('remove', (event, properties) => {
        target.remove(properties.items);
    });
}

function refreshDataWithReplacement(data) {
    const uploaded_service_groups = data.groups.services.map(group => {
        return {
            id: group.id, content: `Service ${group.id}`, nestedGroups: group.containers || null, className: 'service-group',
            title: `Group ${group.id} with containers: ${group.containers ? group.containers.join(', ') : 'none'}`

        }
    });
    const uploaded_container_groups = data.groups.container_groups.map(group => {
        return {
            id: group.id, content: 'Service container with events', title: `Container with id = ${group.id}`, className: 'container-group'
        }
    });

    const uploaded_container_events_items = data.items.points.container_events.map(item => {
        let typeClass = item.type === 'point' ?  : '';
        typeClass += item.myType === 'canBeExploredById' ? ' clickable' : '';
        if (item.src_jsons && item.src_jsons !== null && item.src_jsons !== "null" && !typeClass.includes('clickable')) typeClass += ' clickable';
        const statusClasses = 'event-point clickable' + (typeof item.statuses === 'string' ? item.statuses : (Array.isArray(item.statuses) && item.statuses.length ? item.statuses.join(' ') : '')).trim();
        const className = `${typeClass} ${statusClasses}`
        const time_start = new Date(item.start * 1000);
        const exit_code_str = item.ext_code != null ? `Exit code: ${item.ext_code}` : '';
        const time_end = item.type !== 'point' ? new Date(item.end * 1000) : null;
        return {
            ...item,
            content: item.content.length > 9 ? item.content.substring(0, 6) + '...' : item.content,
            group: item.groupId, // Associate item with a group ID (container or service)
            start: time_start,
            end: time_end,
            title: `Item details: ${item.content} with id = ${item.id}<br>Start time = ${time_start} End time ${time_end} ${exit_code_str}`,
            className: className,
            backend_init: item.myType === 'canBeExploredById' ? {
                method: 'POST',
                headers: { 'Content-Type': 'application/json'},
                body: JSON.stringify({ cont_id: item.id}),
            } : null,
        };
    });


    const items = data.items.map(item => {
        let typeClass = item.type === 'point' ? 'event-point' : '';
        typeClass += item.myType === 'canBeExploredById' ? ' clickable' : '';
        if (item.src_jsons && item.src_jsons !== null && item.src_jsons !== "null" && !typeClass.includes('clickable')) typeClass += ' clickable';
        const statusClasses = typeof item.statuses === 'string' ? item.statuses : (Array.isArray(item.statuses) && item.statuses.length ? item.statuses.join(' ') : '');
        const className = `${typeClass} ${statusClasses}`.trim();
        const time_start = new Date(item.start * 1000);
        const exit_code_str = item.ext_code != null ? `Exit code: ${item.ext_code}` : '';
        const time_end = item.type !== 'point' ? new Date(item.end * 1000) : null;
        return {
            ...item,
            content: item.content.length > 9 ? item.content.substring(0, 6) + '...' : item.content,
            group: item.groupId, // Associate item with a group ID (container or service)
            start: time_start,
            end: time_end,
            title: `Item details: ${item.content} with id = ${item.id}<br>Start time = ${time_start} End time ${time_end} ${exit_code_str}`,
            className: className,
            backend_init: item.myType === 'canBeExploredById' ? {
                method: 'POST',
                headers: { 'Content-Type': 'application/json'},
                body: JSON.stringify({ cont_id: item.id}),
            } : null,
        };
    });
    service_groups.clear();
    service_groups.add(uploaded_service_groups);

    containers_groups.clear();
    containers_groups.add(uploaded_container_groups);

    container_events_items.clear();
    container_events_items.add(data.container_events_items);

    service_events_items.clear();
    service_events_items.add(data.service_events_items);

    container_items.clear();
    container_items.add(data.container_items);

    health_checks_items.clear();
    health_checks_items.add(data.health_checks_items);
}

function refreshDataWithUpdates(data) {
    // Update each dataset with new or modified items
    service_groups.update(data.service_groups);
    containers_groups.update(data.container_groups);
    container_events_items.update(data.container_events_items);
    service_events_items.update(data.service_events_items);
    container_items.update(data.container_items);
    health_checks_items.update(data.health_checks_items);
}

const service_groups = new vis.DataSet([]);
const containers_groups = new vis.DataSet([]);

const container_events_items = new vis.DataSet([]);
const service_events_items = new vis.DataSet([]);
const container_items = new vis.DataSet([]);
const health_checks_items = new vis.DataSet([]);

const all_groups = new vis.DataSet([]);
const all_items = new vis.DataSet([]);

synchronizeDataset(service_groups, all_groups);
synchronizeDataset(containers_groups, all_groups);
synchronizeDataset(container_events_items, all_items);
synchronizeDataset(service_events_items, all_items);
synchronizeDataset(container_items, all_items);
synchronizeDataset(health_checks_items, all_items);

let container = null;
let timeline = null;
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


document.addEventListener('DOMContentLoaded', () => {
    async function loadTimelineData(backend_path='/timeline_data') {
        try {
            document.getElementById('itemsShown').innerHTML = `Items shown: <span class="loading-dots">loading<span>.</span><span>.</span><span>.</span></span>`;
            const timeSelectValue = document.getElementById('timeSelect').value;
            const healthChecks_CheckBox_Value = document.getElementById('healthChecks_CheckBox').checked;
            const load_source_jsons_checkbox_value = document.getElementById('load_source_jsons_checkbox').checked;
            const response = await fetch(backend_path, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json'},
                body: JSON.stringify({ since: timeSelectValue, collect_health_checks: healthChecks_CheckBox_Value, load_source_jsons: load_source_jsons_checkbox_value} ),
            });

            const data = await response.json(); // Parse JSON data
            refreshDataWithReplacement(data)

            document.getElementById('itemsShown').innerText = (` Items shown: ${all_items.length}`);


            // Create the timeline
            if (container == null) container = document.getElementById("visualization");

            if (timeline == null) timeline = new vis.Timeline(container, all_items, all_groups, options);
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
                    if (selectedItem.src_jsons && selectedItem.src_jsons !== null && selectedItem.src_jsons !== "null") {
                        try {
                            const newTab = window.open('', '_blank');
                            if (newTab) {
                                newTab.document.open();
                                const json_data = typeof selectedItem.src_jsons === 'string' ? JSON.parse(selectedItem.src_jsons) : selectedItem.src_jsons;
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
                                            <pre>${JSON.stringify(json_data, null,2)}}</pre>
                                        </body>
                                    </html>
                                `);
                                newTab.document.close();
                            } else {
                                alert("Popup blocker prevented opening a new tab.");
                            }
                        } catch (error) {
                            console.error("Error parsing data:", error);
                            alert("An error occurred while parsing data. Check the console for details.");
                        }
                    }                }
            });
            var group = {
                id: 1, // Unique ID for each group (service or container)
                content: 'Test Group', // Display name for the group
                nestedGroups: ['Nested group 1', 'Nested group 2'],  // Use nested groups for containers under services
                title: 'Test group with two empty nested',
                className: 'service-group' // Add classes for styling
            };
            var item = {
                id: 34654,
                type: 'background',
                group: 1,
                start: new Date(2024, 9, 2, 7, 1, 0),
                end: new Date(2024, 10, 2, 8, 3, 0),
                content: 'Test Item',
                title: 'Test Item'
            };
            all_groups.add(group);
            all_items.add(item)
        } catch (error) {
            document.getElementById('itemsShown').innerHTML = `Error loading timeline data: ${error.message}`;
            console.error(error);
        }
    }
    const refreshButton = document.getElementById('refreshButton');
    refreshButton.addEventListener('click', () => {
        loadTimelineData('/timeline_data');
    });
    loadTimelineData('/timeline_data');
});


