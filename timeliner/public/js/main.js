function refreshDataWithReplacement(data) {
    const uploaded_service_groups = data.groups.services.map(group => {
        return {
            id: group.id, content: `Service ${group.id}`, nestedGroups: group.containers || null,
            title: `Group ${group.id} with containers: ${group.containers ? group.containers.join(', ') : 'none'}`
        }
    });
    const uploaded_container_groups = data.groups.containers.map(group => {
        return {
            id: group.id, content: 'Service container with events', title: `Container with id = ${group.id}`
        }
    });
    const uploaded_container_events_items = data.items.points.container_events.map(item => {
        const statusClasses = item.statuses.length ? ' ' + item.statuses.join(' ') : '';
        const time_start = new Date(item.start * 1000);
        return {
            type: 'point', ext_code: item.ext_code, content: item.action.length > 9 ? item.action.substring(0, 6) + '...' : item.action, src_jsons: item.src_jsons,
            group: item.groupId, start: time_start, end: null, title: `Container event: id = ${item.id}<br>Appeared at ${time_start}; Exit code: ${item.ext_code}`,
            className: 'event-point' + statusClasses + (((item.src_jsons !== undefined) && item.src_jsons === "[]") ? '' : ' clickable')
        };
    });
    const uploaded_service_events_items = data.items.points.service_events.map(item => {
        const statusClasses = item.statuses.length ? ' ' + item.statuses.join(' ') : '';
        const time_start = new Date(item.start * 1000);
        return {
            type: 'point', ext_code: item.ext_code, content: item.action.length > 9 ? item.action.substring(0, 6) + '...' : item.action, src_jsons: item.src_jsons,
            group: item.groupId, start: time_start, end: null, title: `Service event: id = ${item.id}<br>Appeared at ${time_start}; Exit code: ${item.ext_code}`,
            className: 'event-point' + statusClasses + (((item.src_jsons !== undefined) && item.src_jsons === "[]") ? '' : ' clickable')
        };
    });
    const uploaded_containers_items =  data.items.ranges.containers.map(item => {
        const statusClasses = (item.statuses.length) ? (' ' + item.statuses.join(' ')) : '';
        const time_start = new Date(item.start * 1000);
        const time_end = new Date(item.end * 1000);
        return {
            id: item.id, type: 'range', content: 'Container with id: ' + ((item.id.length) > 9 ? item.id.substring(0, 6) + '...' : item.id),
            group: item.groupId, start: time_start, end: time_end,
            title: `Item details: container with id = ${item.id} <br>Start time = ${time_start} End time ${time_end}`,
            className: 'clickable' + statusClasses,
            backend_init: { method: 'POST', headers: { 'Content-Type': 'application/json'}, body: JSON.stringify({ cont_id: item.id}),}
        };
    });
    const uploaded_health_checks_items =  data.items.ranges.health_checks.map(item => {
        const statusClasses = item.statuses.length ? ' ' + item.statuses.join(' ') : '';
        const time_start = new Date(item.start * 1000);
        const time_end = new Date(item.end * 1000);
        return {
            id: item.id, type: 'range', content: 'Health check with id: ' + item.id.length > 9 ? item.id.substring(0, 6) + '...' : item.id,
            group: item.groupId, start: time_start, end: time_end, ext_code: item.ext_code, className: 'clickable' + statusClasses,
            title: `Item details: health check with id = ${item.id} <br>Start time = ${time_start} End time ${time_end} Exit code: ${item.ext_code}`
        };
    });
    service_groups.clear();
    service_groups.add(uploaded_service_groups);

    containers_groups.clear();
    containers_groups.add(uploaded_container_groups);

    container_events_items.clear();
    container_events_items.add(uploaded_container_events_items);

    service_events_items.clear();
    service_events_items.add(uploaded_service_events_items);

    containers_items.clear();
    containers_items.add(uploaded_containers_items);

    health_checks_items.clear();
    health_checks_items.add(uploaded_health_checks_items);
}


const service_groups = new vis.DataSet([]);
const containers_groups = new vis.DataSet([]);

const container_events_items = new vis.DataSet([]);
const service_events_items = new vis.DataSet([]);
const containers_items = new vis.DataSet([]);
const health_checks_items = new vis.DataSet([]);

let all_groups = null;
let all_items = null;

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

let isLoading = false;


document.addEventListener('DOMContentLoaded', () => {
    async function loadTimelineData(backend_path='/timeline_data') {
        if (isLoading) {
            window.alert('Loading in progress, please, wait for it to finish');
            return;
        }
        isLoading = true;
        try {
            document.getElementById('itemsShown').innerHTML = `Items shown: <span class="loading-dots">loading<span>.</span><span>.</span><span>.</span></span>`;
            const timeSelectValue = document.getElementById('timeSelect').value;
            const healthChecks_CheckBox_Value = document.getElementById('healthChecks_CheckBox').checked;
            const load_source_jsons_checkbox_value = document.getElementById('load_source_jsons_checkbox').checked;
            const response = await fetch(backend_path, {
                method: 'POST', headers: { 'Content-Type': 'application/json'}, body: JSON.stringify({ since: timeSelectValue, collect_health_checks: healthChecks_CheckBox_Value, load_source_jsons: load_source_jsons_checkbox_value} ),
            });
            const data = await response.json(); // Parse JSON data
            refreshDataWithReplacement(data)
            all_groups = new vis.DataSet(service_groups.get().concat(containers_groups.get()));
            all_items = new vis.DataSet(container_events_items.get().concat(service_events_items.get().concat(containers_items.get().concat(health_checks_items.get()))));
            document.getElementById('itemsShown').innerText = (` Items shown: ${all_items.length}`);
            if (container == null) container = document.getElementById("visualization");
            if (timeline == null) {
                timeline = new vis.Timeline(container, all_items, all_groups, options);
                timeline.on('select', async function (properties) {
                    const selectedItemId = properties.items[0];
                    if (selectedItemId) {
                        const selectedItem = all_items.get(selectedItemId);
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
                                }
                            } catch (error) {
                                console.error("Error fetching data:", error);
                                alert("An error occurred while fetching data. Check the console for details.");
                            }
                        }
                        if ((selectedItem.src_jsons !== undefined) && (selectedItem.src_jsons !== "[]")) {
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
                                }
                            } catch (error) {
                                console.error("Error parsing data:", error);
                                alert("An error occurred while parsing data. Check the console for details.");
                            }
                        }
                    }
                });
            }
            window.addEventListener("resize", () => timeline.redraw());
            timeline.setItems(all_items);
            timeline.setGroups(all_groups);
        } catch (error) {
            document.getElementById('itemsShown').innerHTML = `Error loading timeline data: ${error.message}`;
            console.error(error);
        } finally {
            isLoading = false;
        }
    }
    const refreshButton = document.getElementById('refreshButton');
    refreshButton.addEventListener('click', () => {
        loadTimelineData('/timeline_data');
    });
    loadTimelineData('/timeline_data');
});


