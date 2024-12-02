const spin = () => {
    document.getElementById("dman").classList += " spin";
};

const triggerManualCheck = () => {
    fetch("triggerManualCheck", {
        method: "POST",
    }).then((res) => {
        if (res.status === 201) {
            window.location.reload();
        } else {
            res.text().then(alert);
        }
    });
};