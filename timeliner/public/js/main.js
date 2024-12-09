const CONTAINER_START_ACTIONS = ['create', 'start'];
const CONTAINER_STOP_ACTIONS = ['destroy', 'die', 'kill', 'stop'];

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
    const uploaded_unknown_service_subgroups = data.groups.unknown_service_subgroups.map(group => {
        return {
            id: group.id, content: `Unknown group with id: ${group.id}`, title: `For this subgroup service is unknown.\n But actions froms this group has shared id = ${group.id}`
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
    const uploaded_other_service_events_items = data.items.points.service_events.other_events.map(item => {
        const statusClasses = item.statuses.length ? ' ' + item.statuses.join(' ') : '';
        const time_start = new Date(item.start * 1000);
        return {
            type: 'point', ext_code: item.ext_code, content: item.action.length > 9 ? item.action.substring(0, 6) + '...' : item.action, src_jsons: item.src_jsons,
            group: item.groupId, start: time_start, end: null, title: `Service event: id = ${item.id}<br>Appeared at ${time_start}; Exit code: ${item.ext_code}`,
            className: 'event-point' + statusClasses + (((item.src_jsons !== undefined) && item.src_jsons === "[]") ? '' : ' clickable')
        };
    });
    const uploaded_image_update_service_events_items = data.items.points.service_events.image_updates.map(item => {
        const time_start = new Date(item.start * 1000);
        return {
            type: 'point', content: 'Image update', src_jsons: item.src_jsons,
            group: item.groupId, start: time_start, end: null, title: `Service image update event: id = ${item.id}<br>Image = ${item.image}<br>Appeared at ${time_start}`,
            className: 'event-point neutral' + (((item.src_jsons !== undefined) && item.src_jsons === "[]") ? '' : ' clickable')
        };
    });
    const uploaded_service_update_events = data.items.points.service_events.service_updates.map(item => {
        const time_start = new Date(item.start * 1000);
        return {
            type: 'point', content: 'Service update', src_jsons: item.src_jsons,
            group: item.groupId, start: time_start, end: null, title: `Service update: id = ${item.id}<br>Appeared at ${time_start};State = ${item.update_state}`,
            className: 'event-point neutral' + (((item.src_jsons !== undefined) && item.src_jsons === "[]") ? '' : ' clickable')
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
            idFofLogs: item.id
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
    const uploaded_unknown_service_group_event_items = data.items.points.unknown_service_group_events.map(item => {
        const statusClasses = item.statuses.length ? ' ' + item.statuses.join(' ') : '';
        const time_start = new Date(item.start * 1000);
        return {
            type: 'point', ext_code: item.ext_code, content: item.action.length > 9 ? item.action.substring(0, 6) + '...' : item.action, src_jsons: item.src_jsons,
            group: item.groupId, start: time_start, end: null, title: `Event with unknown service: id = ${item.id}<br>Appeared at ${time_start}; Exit code: ${item.ext_code}`,
            className: 'event-point' + (((item.src_jsons !== undefined) && item.src_jsons === "[]") ? '' : ' clickable')
        };
    });
    service_groups.clear();
    service_groups.add(uploaded_service_groups);

    containers_groups.clear();
    containers_groups.add(uploaded_container_groups);

    unknown_service_subgroups.clear();
    unknown_service_subgroups.add(uploaded_unknown_service_subgroups);


    unknown_service_group.clear();
    if (uploaded_unknown_service_subgroups.size > 0) {
        unknown_service_group.add({id: "Unknown service group", content: "Groups and events without service",
            nestedGroups: uploaded_unknown_service_subgroups.map(), title: "This group unite subgroups, which don't have service"});
    }

    container_events_items.clear();
    container_events_items.add(uploaded_container_events_items);

    other_service_events_items.clear();
    other_service_events_items.add(uploaded_other_service_events_items);

    image_update_service_events_items.clear();
    image_update_service_events_items.add(uploaded_image_update_service_events_items);

    service_update_events.clear();
    service_update_events.add(uploaded_service_update_events);

    containers_items.clear();
    containers_items.add(uploaded_containers_items);

    health_checks_items.clear();
    health_checks_items.add(uploaded_health_checks_items);

    unknown_service_group_event_items.clear();
    unknown_service_group_event_items.add(uploaded_unknown_service_group_event_items);
}

function filter_container_events(container_events_dataset, tracking_events, take=false, container_id = ""){
    return container_events_dataset.get({
        filter: function (item){
            return (container_id === "" ? true : item.group === container_id) && (take === tracking_events.some(event => item.content.includes(event)));
        }
    });
}
async function inspectContainerEvents(selectedItemId, listOfEvents) {
    const start_container_events = filter_container_events(container_events_items, listOfEvents, true, selectedItemId);
    try {
        const newTab = window.open('', '_blank');
        if (newTab) {
            newTab.document.open();
            // Parse src_jsons for each event before stringifying
            const processed_events = start_container_events.map(event => {
                if (event.src_jsons) {
                    try {
                        // Parse the double-nested JSON structure
                        event.src_jsons = JSON.parse(event.src_jsons).map(jsonArray =>
                            jsonArray.map(item => JSON.parse(JSON.stringify(item)))[0]
                        );
                    } catch (e) {
                        console.warn(`Failed to parse src_jsons for event ${event.id}:`, e);
                        // Keep original if parsing fails
                    }
                }
                return event;
            });

            const json_data = JSON.stringify(processed_events, null, 5);
            newTab.document.write(`
                <html>
                    <head>
                        <title>Start events inspection</title>
                        <style>
                            body { font-family: Arial, sans-serif; padding: 20px; }
                            pre { background: #f4f4f4; padding: 10px; border: 1px solid #ddd; }
                        </style>
                    </head>
                    <body>
                        <h1>Container ${selectedItemId} start events inspection</h1>
                        <pre>${json_data}</pre>
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
async function inspectStartEvents(selectedItemId){
    await inspectContainerEvents(selectedItemId, CONTAINER_START_ACTIONS);
}
async function inspectEndEvents(selectedItemId){
    await inspectContainerEvents(selectedItemId, CONTAINER_STOP_ACTIONS);
}


const service_groups = new vis.DataSet([]);
const containers_groups = new vis.DataSet([]);
const unknown_service_group = new vis.DataSet([]);
const unknown_service_subgroups = new vis.DataSet([]);

const container_events_items = new vis.DataSet([]);
const other_service_events_items = new vis.DataSet([]);
const image_update_service_events_items = new vis.DataSet([]);
const service_update_events = new vis.DataSet([]);
const containers_items = new vis.DataSet([]);
const health_checks_items = new vis.DataSet([]);
const unknown_service_group_event_items = new vis.DataSet([]);

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
    showCurrentTime: false,
    zoomKey: 'ctrlKey'
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
            all_groups = new vis.DataSet(service_groups.get().concat(
                containers_groups.get().concat(
                    unknown_service_group.get().concat(
                        unknown_service_subgroups.get()
                    )
                )
            ));
            all_items = new vis.DataSet(filter_container_events(container_events_items, CONTAINER_START_ACTIONS.concat(CONTAINER_STOP_ACTIONS), false).concat(
                image_update_service_events_items.get().concat(
                    other_service_events_items.get().concat(
                        service_update_events.get().concat(
                            containers_items.get().concat(
                                health_checks_items.get().concat(
                                    unknown_service_group_event_items.get()
                                )
                            )
                        )
                    )
                )
            ));
            document.getElementById('itemsShown').innerText = (` Items shown: ${all_items.length}`);
            if (container == null) container = document.getElementById("visualization");
            if (timeline == null) {
                timeline = new vis.Timeline(container, all_items, all_groups, options);
                timeline.on('contextmenu', function (props) {
                    const selectedItemId = props.item;
                    if (selectedItemId) {
                        const selectedItem = all_items.get(selectedItemId);
                        if (selectedItem.idFofLogs) {
                            const menu = document.createElement('div');
                            menu.className = 'context-menu';
                            menu.style.position = 'absolute';
                            menu.style.left = props.pageX + 'px';
                            menu.style.top = props.pageY + 'px';
                            menu.style.backgroundColor = '#ffffff';
                            menu.style.border = '1px solid #ccc';
                            menu.style.borderRadius = '4px';
                            menu.style.boxShadow = '0 2px 5px rgba(0,0,0,0.2)';
                            menu.style.padding = '5px 0';
                            menu.innerHTML = `
                                <div class="menu-item" onmouseover="this.style.backgroundColor='#f0f0f0'" onmouseout="this.style.backgroundColor='transparent'" style="padding: 8px 15px; cursor: pointer; border-bottom: 1px solid #eee;" onclick="inspectStartEvents('${selectedItemId}')">Inspect start events</div>
                                <div class="menu-item" onmouseover="this.style.backgroundColor='#f0f0f0'" onmouseout="this.style.backgroundColor='transparent'" style="padding: 8px 15px; cursor: pointer;" onclick="inspectEndEvents('${selectedItemId}')">Inspect end events</div>
                            `;
                            document.body.appendChild(menu);

                            const closeMenu = () => {
                                document.body.removeChild(menu);
                                document.removeEventListener('click', closeMenu);
                                document.removeEventListener('mousemove', handleMouseMove);
                            };

                            const handleMouseMove = (e) => {
                                const menuRect = menu.getBoundingClientRect();
                                const distance = Math.sqrt(
                                    Math.pow(e.clientX - (menuRect.left + menuRect.width/2), 2) +
                                    Math.pow(e.clientY - (menuRect.top + menuRect.height/2), 2)
                                );
                                if (distance > 100) { // disappear if mouse is more than 100px away
                                    closeMenu();
                                }
                            };

                            setTimeout(() => {
                                document.addEventListener('click', closeMenu);
                                document.addEventListener('mousemove', handleMouseMove);
                            }, 0);
                        }
                    }
                    props.event.preventDefault();
                });
                timeline.on('select', async function (properties) {
                    const selectedItemId = properties.items[0];
                    if (selectedItemId) {
                        const selectedItem = all_items.get(selectedItemId);
                        if (selectedItem.idFofLogs) {
                            const newTab = window.open('', '_blank')
                            if (newTab) {
                                newTab.location.href = '/logs/cid/' + selectedItem.idFofLogs;
                            }
                            return;
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
                                            <title>Source JSON inspection</title>
                                            <style>
                                                body { font-family: Arial, sans-serif; padding: 20px; }
                                                pre { background: #f4f4f4; padding: 10px; border: 1px solid #ddd; }
                                            </style>
                                        </head>
                                        <body>
                                            <h1>Source JSON inspection</h1>
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


