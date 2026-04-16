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
var ASSET_VERSION = "20260415g";

function initPage() {
    populateMetadata();
}

function normalizeProfile(rawProfile) {
    var map = {
        "Auto": "auto",
        "Portrait Small": "portrait-small",
        "Portrait Large": "portrait-large",
        "Landscape Small": "landscape-small",
        "Landscape Large": "landscape-large",
        "auto": "auto",
        "portrait-small": "portrait-small",
        "portrait-large": "portrait-large",
        "landscape-small": "landscape-small",
        "landscape-large": "landscape-large"
    };
    return map[rawProfile] || rawProfile || "auto";
}

function getProfileClass() {
    var raw = normalizeProfile(config.profile || "auto");
    if (raw === "auto") {
        return window.innerWidth > window.innerHeight ? "auto-landscape" : "auto-portrait";
    }
    return raw;
}

function applyBodyClasses() {
    document.body.classList.remove(
        "profile-portrait-small",
        "profile-portrait-large",
        "profile-landscape-small",
        "profile-landscape-large",
        "profile-auto-portrait",
        "profile-auto-landscape",
        "nomedia-clockonly",
        "nomedia-stacked"
    );

    var appliedProfileClass = "profile-" + getProfileClass();
    document.body.classList.add(appliedProfileClass);
    document.body.classList.add(config.noMediaLayout === "Clock Only" ? "nomedia-clockonly" : "nomedia-stacked");
    document.body.setAttribute("data-room-id", roomId || "");
    document.body.setAttribute("data-config-profile", config.profile || "");
    document.body.setAttribute("data-applied-profile", appliedProfileClass);
    document.body.setAttribute("data-show-logo", config.showLogo === false ? "false" : "true");
}

function getRoomId() {
    var path = window.location.pathname || "";
    var parts = path.split('/').filter(Boolean);
    for (var i = parts.length - 1; i >= 0; i--) {
        if (/^\d+$/.test(parts[i])) return parts[i];
    }
    return parts.length ? parts[0] : "";
}

function loadConfig() {
    try {
        var raw = urlCall('/config/' + roomId + '?_=' + new Date().getTime());
        var parsed = parseJSON(raw || '{}');

        if (typeof parsed === 'string') {
            parsed = parseJSON(parsed || '{}');
        }

        if (parsed && typeof parsed === 'object') {
            config = parsed;
        }
        try { console.log('C4 config for room', roomId, config); } catch (e2) {}
    } catch (e) {
        try { console.log('C4 config load failed for room', roomId, e); } catch (e2) {}
        config = config || {};
    }

    if (!config.profile) config.profile = "auto";
    if (!config.burnInMode) config.burnInMode = "Clock Corners";
    if (!config.noMediaLayout) config.noMediaLayout = "Stacked";
    if (typeof config.showWeather !== 'boolean') config.showWeather = true;
    if (typeof config.showLogo !== 'boolean') config.showLogo = true;
    if (!config.weatherSource) config.weatherSource = 'Weather.gov';

    applyBodyClasses();
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
    var clockEl = document.getElementById("clock");
    var ampmEl = document.getElementById("ampm");
    var dowEl = document.getElementById("dayofweek");
    var dayEl = document.getElementById("day");
    var monthEl = document.getElementById("month");
    if (clockEl) clockEl.innerHTML = hours + ':' + minutes;
    if (ampmEl) ampmEl.innerHTML = ampm;
    if (dowEl) dowEl.innerHTML = dayName;
    if (dayEl) dayEl.innerHTML = dayNum;
    if (monthEl) monthEl.innerHTML = monthName;
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

        var titleEl = document.getElementById("title");
        var artistEl = document.getElementById("artist");
        var albumEl = document.getElementById("album");
        var artEl = document.getElementById("art");

        if (!jsonData.title && !jsonData.artist && !jsonData.album) {
            if (titleEl) titleEl.innerHTML = jsonData.devicename || "";
            if (artistEl) artistEl.innerHTML = "";
            if (albumEl) albumEl.innerHTML = "";
        } else {
            if (titleEl) titleEl.innerHTML = jsonData.title || "";
            if (artistEl) artistEl.innerHTML = jsonData.artist || "";
            if (albumEl) albumEl.innerHTML = jsonData.album || "";
        }
        if (artEl) artEl.src = jsonData.img || 'png/default_cover_art.png';

        var logo = document.getElementById("source-logo");
        var logoContainer = document.getElementById("source-logo-container");
        if (logo && logoContainer) {
            var icon = jsonData.sourceicon || jsonData.deviceicon || jsonData.serviceicon || jsonData.displayicon || "";
            if (config.showLogo && icon && typeof icon === "string" && icon.trim() !== "") {
                logo.src = icon;
                logo.style.display = "block";
                logoContainer.style.display = "flex";
            } else {
                logo.removeAttribute("src");
                logo.style.display = "none";
                logoContainer.style.display = "none";
            }
        }

        oldData = data;
    }
}

function updateWeather() {
    if (!config.showWeather) {
        var temp = document.getElementById("temp");
        if (temp) temp.style.display = 'none';
        return;
    } else {
        var tempBlock = document.getElementById("temp");
        if (tempBlock) tempBlock.style.display = '';
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
    var tempNum = document.getElementById("temp-num");
    var scaleEl = document.getElementById("scale");
    if (tempNum) tempNum.innerHTML = Math.round(tempVal);
    if (scaleEl) scaleEl.innerHTML = scale;
}

function arrangeContent(media) {
    var main_container = document.getElementById("main-container");
    var metadata_container = document.getElementById("metadata-container");
    var date_time_temp_container = document.getElementById("date-time-temp-container");
    var transition_time;

    updating = true;
    setTimeout(function(){ updating = false; }, 3000);

    if (init === false) {
        setTimeout(function(){ if(main_container) main_container.classList.toggle('fade'); }, 0);
        setTimeout(function(){ if(main_container) main_container.classList.toggle('fade'); }, 1700);
        transition_time = 1000;
    } else {
        transition_time = 0;
    }

    if (!media) {
        setTimeout(function(){ if(metadata_container) metadata_container.innerHTML = ''; }, transition_time);
        setTimeout(function(){ if(date_time_temp_container) date_time_temp_container.innerHTML = original_date_time_temp_container; }, transition_time);
        setTimeout(function(){ swapStyleSheet('css/nomedia.css'); }, transition_time);
        oldData = '';
        currentMode = 'nomedia';
        noMediaPos = 0;
        applyPositionForMode();
        applyBodyClasses();
    } else {
        oldData = '';
        setTimeout(function(){ if(date_time_temp_container) date_time_temp_container.innerHTML = original_date_time_temp_container; }, transition_time);
        setTimeout(function(){ if(metadata_container) metadata_container.innerHTML = original_metadata_container; }, transition_time);
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
    if (!main_container) return;
    main_container.classList.remove('mpos0', 'mpos1', 'npos0', 'npos1', 'npos2', 'npos3', 'nomedia-clockonly');
}

function applyPositionForMode() {
    var main_container = document.getElementById('main-container');
    clearPositionClasses(main_container);
    if (!main_container) return;

    if (currentMode === 'media') {
        if (config.burnInMode === 'Off') mediaPos = 0;
        main_container.classList.add('mpos' + mediaPos);
    } else if (currentMode === 'nomedia') {
        if (config.burnInMode === 'Off') noMediaPos = 0;
        main_container.classList.add('npos' + noMediaPos);
        if (config.noMediaLayout === 'Clock Only') {
            main_container.classList.add('nomedia-clockonly');
        }
    }
}

function transitionLayout() {
    var main_container = document.getElementById('main-container');
    if (!main_container || config.burnInMode === 'Off') return;

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
            while (next === noMediaPos) next = Math.floor(Math.random() * 4);
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
    var joiner = sheet.indexOf('?') >= 0 ? '&' : '?';
    document.getElementById('layout-stylesheet').setAttribute('href', sheet + joiner + 'v=' + ASSET_VERSION);
}

function repopulateForResize() {
    applyBodyClasses();
    applyPositionForMode();
}

function populateMetadata() {
    roomId = getRoomId();
    loadConfig();

    document.addEventListener('visibilitychange', function() {
        if (!document.hidden) {
            loadConfig();
            applyPositionForMode();
        }
    });
    window.addEventListener('focus', function() {
        loadConfig();
        applyPositionForMode();
    });

    original_metadata_container = document.getElementById('metadata-container').innerHTML;
    original_date_time_temp_container = document.getElementById('date-time-temp-container').innerHTML;

    updateClock();
    updateMetadata();
    if (config.showWeather) updateWeather();

    window.addEventListener('resize', repopulateForResize);

    clockTimer = setInterval(updateClock, 1000);
    metadataTimer = setInterval(updateMetadata, 1000);
    if (config.showWeather && config.weatherSource === 'Weather.gov') {
        weatherTimer = setInterval(updateWeather, 300000);
    }
    transitionTimer = setInterval(transitionLayout, 300000);
    setTimeout(function(){ init = false; }, 3000);
}
