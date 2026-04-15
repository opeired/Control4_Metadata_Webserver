var original_metadata_container;
var original_date_time_temp_container;
var clockTimer;
var metadataTimer;
var weatherTimer;
var transitionTimer;
var oldData;
var init = true;
var updating = false;
var currentMode = "unknown";
var mediaPos = 0;
var noMediaPos = 0;
var roomId = "";
var config = window.C4_CONFIG || {};

function normalizeProfile(rawProfile) {
    if (!rawProfile || rawProfile === "auto") {
        return window.innerWidth > window.innerHeight ? "landscape-large" : "portrait-small";
    }
    return rawProfile;
}

function currentProfileClass() {
    var profile = normalizeProfile(config.profile);
    if (profile.indexOf("portrait") === 0) return profile;
    if (profile.indexOf("landscape") === 0) return profile;
    return window.innerWidth > window.innerHeight ? "auto-landscape" : "auto-portrait";
}

function applyBodyClasses() {
    document.body.className = "";
    var profile = normalizeProfile(config.profile);
    var profileClass = profile;
    if (config.profile === "auto") {
        profileClass = window.innerWidth > window.innerHeight ? "auto-landscape" : "auto-portrait";
    }
    document.body.classList.add("profile-" + profileClass);
    document.body.classList.add(config.noMediaLayout === "Clock Only" ? "nomedia-clockonly" : "nomedia-stacked");
}

function getRoomId() {
    var path = window.location.pathname || "";
    var parts = path.split('/').filter(Boolean);
    return parts.length ? parts[0] : "";
}

function updateClock() {
    var date = new Date();
    var hours = date.getHours();
    var minutes = date.getMinutes();
    var days = ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];
    var dayName = days[date.getDay()];
    var dayNum = date.getDate();
    var months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
    var monthName = months[date.getMonth()];
    var ampm = hours >= 12 ? 'PM' : 'AM';
    hours = hours % 12;
    hours = hours ? hours : 12;
    minutes = minutes < 10 ? '0' + minutes : minutes;
    document.getElementById("clock").innerHTML = hours + ':' + minutes;
    document.getElementById("ampm").innerHTML = ampm;
    document.getElementById("dayofweek").innerHTML = dayName;
    document.getElementById("day").innerHTML = dayNum;
    document.getElementById("month").innerHTML = monthName;
}

function updateMetadata() {
    var data = urlCall('/' + roomId + '/json');
    var jsonData = parseJSON(data || '{}');
    var hasMedia = !(jsonData.title == null && jsonData.artist == null && jsonData.album == null && jsonData.img == null);

    if (!hasMedia) {
        if (currentMode !== "nomedia" && updating === false) {
            arrangeContent(false);
        }
        return;
    } else {
        if (currentMode !== "media" && updating === false) {
            arrangeContent(true);
            return;
        }
    }

    if (data !== oldData) {
        if (jsonData.img === "") {
            jsonData.img = 'png/default_cover_art.png';
        }
        if (!jsonData.title && !jsonData.artist && !jsonData.album) {
            document.getElementById("title").innerHTML = jsonData.devicename || "";
            document.getElementById("artist").innerHTML = "";
            document.getElementById("album").innerHTML = "";
        } else {
            document.getElementById("title").innerHTML = jsonData.title || "";
            document.getElementById("artist").innerHTML = jsonData.artist || "";
            document.getElementById("album").innerHTML = jsonData.album || "";
        }
        document.getElementById("art").src = jsonData.img || 'png/default_cover_art.png';
        oldData = data;
    }
}

function updateWeather() {
    if (!config.showWeather) {
        var temp = document.getElementById("temp");
        if (temp) temp.style.display = 'none';
        return;
    }

    if (config.weatherSource !== 'Weather.gov') {
        return;
    }

    var projectData = parseJSON(urlCall('/project') || '{}');
    if (!projectData.latitude || !projectData.longitude) {
        return;
    }

    var weatherUrl1 = 'https://api.weather.gov/points/' + projectData.latitude + ',' + projectData.longitude;
    var weatherData1 = parseJSON(urlCall(weatherUrl1) || '{}');
    if (!weatherData1.properties || !weatherData1.properties.forecastHourly) {
        return;
    }
    var weatherData2 = parseJSON(urlCall(weatherData1.properties.forecastHourly) || '{}');
    if (!weatherData2.properties || !weatherData2.properties.periods || !weatherData2.properties.periods.length) {
        return;
    }

    var tempVal = weatherData2.properties.periods[0].temperature;
    var scale = 'F';
    if (projectData.scale === 'CELSIUS') {
        tempVal = (tempVal - 32) * 5 / 9;
        scale = 'C';
    }
    document.getElementById("temp-num").innerHTML = Math.round(tempVal);
    document.getElementById("scale").innerHTML = scale;
}

function arrangeContent(media) {
    var main_container = document.getElementById("main-container");
    var metadata_container = document.getElementById("metadata-container");
    var date_time_temp_container = document.getElementById("date-time-temp-container");
    var transition_time;

    updating = true;
    setTimeout(function(){ updating = false; }, 3000);

    if (init === false) {
        setTimeout(function(){ main_container.classList.toggle('fade'); }, 0);
        setTimeout(function(){ main_container.classList.toggle('fade'); }, 1700);
        transition_time = 1000;
    } else {
        transition_time = 0;
    }

    if (!media) {
        setTimeout(function(){ metadata_container.innerHTML = ''; }, transition_time);
        setTimeout(function(){ date_time_temp_container.innerHTML = original_date_time_temp_container; }, transition_time);
        setTimeout(function(){ swapStyleSheet('css/nomedia.css'); }, transition_time);
        oldData = '';
        currentMode = 'nomedia';
        noMediaPos = 0;
        applyPositionForMode();
        applyBodyClasses();
    } else {
        oldData = '';
        setTimeout(function(){ date_time_temp_container.innerHTML = original_date_time_temp_container; }, transition_time);
        setTimeout(function(){ metadata_container.innerHTML = original_metadata_container; }, transition_time);
        setTimeout(function(){ swapStyleSheet('css/media.css'); }, transition_time);
        setTimeout(function(){ updateMetadata(); }, transition_time + 200);
        setTimeout(function(){ updateWeather(); }, transition_time + 200);
        currentMode = 'media';
        mediaPos = 0;
        applyPositionForMode();
        applyBodyClasses();
    }
}

function clearPositionClasses(main_container) {
    main_container.classList.remove('mpos0', 'mpos1', 'npos0', 'npos1', 'npos2', 'npos3', 'nomedia-clockonly');
}

function applyPositionForMode() {
    var main_container = document.getElementById('main-container');
    clearPositionClasses(main_container);
    if (currentMode === 'media') {
        if (config.burnInMode === 'Off') {
            mediaPos = 0;
        }
        main_container.classList.add('mpos' + mediaPos);
    } else if (currentMode === 'nomedia') {
        if (config.burnInMode === 'Off') {
            noMediaPos = 0;
        }
        main_container.classList.add('npos' + noMediaPos);
        if (config.noMediaLayout === 'Clock Only') {
            main_container.classList.add('nomedia-clockonly');
        }
    }
}

function transitionLayout() {
    var main_container = document.getElementById('main-container');
    if (config.burnInMode === 'Off') {
        return;
    }

    setTimeout(function(){ main_container.classList.toggle('fade'); }, 0);

    if (currentMode === 'media') {
        if (config.burnInMode === 'Clock Corners' || config.burnInMode === 'Shuffle') {
            mediaPos = (mediaPos + 1) % 2;
        }
    } else if (currentMode === 'nomedia') {
        if (config.noMediaLayout === 'Clock Only' || config.burnInMode === 'Clock Corners') {
            noMediaPos = (noMediaPos + 1) % 4;
        } else {
            var next = noMediaPos;
            while (next === noMediaPos) {
                next = Math.floor(Math.random() * 4);
            }
            noMediaPos = next;
        }
    }

    applyPositionForMode();
    setTimeout(function(){ main_container.classList.toggle('fade'); }, 1500);
}

function urlCall(url) {
    var xmlHttp = new XMLHttpRequest();
    xmlHttp.open('GET', url, false);
    xmlHttp.send(null);
    return xmlHttp.responseText;
}

function parseJSON(json) {
    try {
        return JSON.parse(json);
    } catch (e) {
        return {};
    }
}

function swapStyleSheet(sheet) {
    document.getElementById('layout-stylesheet').setAttribute('href', sheet);
}

function populateMetadata() {
    roomId = getRoomId();
    if (!config.profile) {
        config = parseJSON(urlCall('/config/' + roomId) || '{}');
    }
    original_metadata_container = document.getElementById('metadata-container').innerHTML;
    original_date_time_temp_container = document.getElementById('date-time-temp-container').innerHTML;

    applyBodyClasses();
    updateClock();
    updateMetadata();
    if (config.showWeather) updateWeather();

    clockTimer = setInterval(updateClock, 1000);
    metadataTimer = setInterval(updateMetadata, 1000);
    if (config.showWeather && config.weatherSource === 'Weather.gov') {
        weatherTimer = setInterval(updateWeather, 300000);
    }
    transitionTimer = setInterval(transitionLayout, 300000);
    setTimeout(function(){ init = false; }, 3000);
}
