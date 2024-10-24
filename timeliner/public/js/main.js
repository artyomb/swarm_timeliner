function gup(name) {
  name = name.replace(/[\[]/, "\\[").replace(/[\]]/, "\\]");
  var regexS = "[\\?&]" + name + "=([^&#]*)";
  var regex = new RegExp(regexS);
  var results = regex.exec(window.location.href);
  if (results == null) return "";
  else return results[1];
}

// get selected item count from url parameter
var count = Number(gup("count")) || 1000;

async function loadTimelineData() {
  try {
      const response = await fetch('/timeline_data', {
          method: 'POST', headers: { 'Content-Type': 'application/json'},
          body: JSON.stringify({ count: count})
      });

      const data = await response.json(); // Parse JSON data
      const groups = new vis.DataSet(data.groups); // Use groups from the backend response
      const items = new vis.DataSet(data.items.map(item => {
          if (item.type === 'point') {
              // For events with a single timestamp (point-in-time), only set the start date
              return {
                  ...item,
                  start: new Date(item.timestamp / 10**6), // Convert timestamp to Date object
                  type: 'point', // Mark this as a point event
                  title: `Event Details: ${item.content} occurred at ${new Date(item.timestamp / 10**6)}`
              };
          } else if (item.continuous && item.end == -1) {
              return {
                  ...item,
                  start: new Date(item.start / 10 ** 6),
                  end: new Date(),
              }
          }
          else {
              // For events with a time range, set both start and end
              return {
                  ...item,
                  start: new Date(item.start / 10**6), // Convert start timestamp to Date object
                  end: new Date(item.end / 10**6),      // Convert end timestamp to Date object
              };
          }
      }));
      // Specify options for the timeline
      var options = {
          stack: true,
          start: new Date(new Date().setHours(0, 0, 0, 0)),
          end: new Date(1000 * 60 * 60 * 24 + new Date().valueOf()),
          editable: false,
          margin: {
              item: 10, // Minimal margin between items
              axis: 5, // Minimal margin between items and the axis
          },
          orientation: "top",
          order: function (a, b) {
              // Point events come first
              if (a.type === 'point' && b.type !== 'point') {
                  return -1;
              } else if (a.type !== 'point' && b.type === 'point') {
                  return 1;
              }
              // Otherwise sort by start date
              return a.start - b.start;
          }
      };

      // Create the timeline
      var container = document.getElementById("visualization");
      var timeline = new vis.Timeline(container, items, options);
      timeline.setGroups(groups);
      window.addEventListener("resize", () => {
          timeline.redraw();
      });
      timeline.on('select', function (properties) {
          const selectedItemId = properties.items[0]; // Get the ID of the selected item
          if (selectedItemId) {
              const selectedItem = items.get(selectedItemId); // Get the selected item details

              // Check if the item has the backend_path field
              if (selectedItem.backend_path) {
                  const url = `/get-container-logs/${selectedItem.backend_path}`;
                  window.location.href = url; // Redirect the browser to the generated URL
              }
          }
      });
  } catch (error) {
      document.getElementById("count").innerHTML = "Error handled with error: " + error;
      console.error("Error loading timeline data:", error);
  }
}// Call the function to load the timeline data
loadTimelineData();