#!/bin/bash


set -e

#sed is replacing the polaris version with this commit sha so we are testing exactly this verison.
sed -ri "s|'(quay.io/reactiveops/polaris:).+'|'\1${CIRCLE_SHA1}'|" ./deploy/webhook.yaml

# Testing to ensure that the webhook starts up, allows a correct deployment to pass,
# and prevents a incorrectly formatted deployment. 
function check_webhook_is_ready() {
    echo "Waiting for webhook to be ready"
    # Get the epoch time in one minute from now
    local timeout_epoch=$(date -d "+1 minute" +%s)
    # loop until this fails (desired condition is we cannot apply this yaml doc, which means the webhook is working
    while kubectl apply -f test/failing_test.deployment.yaml &>/dev/null; do
        if [[ "$(date +%s)" -ge "${timeout_epoch}" ]]; then
            echo -e "Timeout hit waiting for webhook readiness: exiting"
            grab_logs
            clean_up
            exit 1
        fi
        echo -n "."
        kubectl delete -f test/failing_test.deployment.yaml &>/dev/null || true
    done
    # clean up the test (the "or true" is to catch the condition that it couldn't delete something
    echo "Webhook started!"
}

# Clean up all your stuff
function clean_up() {
    # Clean up files you've installed (helps with local testing)
    for filename in test/*yaml; do
        # || true to avoid issues when we cannot delete
        kubectl delete -f $filename &>/dev/null ||true
    done
    # Uninstall webhook and webhook config
    kubectl delete -f deploy/webhook.yaml --wait=false &>/dev/null
    kubectl delete validatingwebhookconfigurations polaris-webhook --wait=false &>/dev/null
}

function grab_logs() {
    kubectl -n polaris get pods -oyaml -l app=polaris
    kubectl -n polaris logs -l app=polaris
}

# Install the webhook
kubectl apply -f ./deploy/webhook.yaml &> /dev/null

# wait for the webhook to come online
check_webhook_is_ready

# Webhook started, setting all tests as passed initially.
ALL_TESTS_PASSED=1

# Run tests against correctly configured objects
for filename in test/passing_test.*.yaml; do
    echo $filename
    if ! kubectl apply -f $filename &> /dev/null; then
        ALL_TESTS_PASSED=0
        echo "Test Failed: Polaris prevented a deployment with no configuration issues." 
    fi
done

# Run tests against incorrectly configured objects
for filename in test/failing_test.*.yaml; do
    echo $filename
    if kubectl apply -f $filename &> /dev/null; then
        ALL_TESTS_PASSED=0
        echo "Test Failed: Polaris should have prevented this deployment due to configuration issues."
    fi
done

clean_up

#Verify that all the tests passed.
if [ $ALL_TESTS_PASSED -eq 1 ]; then
    echo "Tests Passed."
else
    echo "Tests Failed."
    exit 1
fi
