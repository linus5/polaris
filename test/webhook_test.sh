#!/bin/bash

#Testing to ensure that the webhook starts up, allows a correct deployment to pass,
#and prevents a incorrectly formatted deployment. 
set -e
#sed is replacing the polaris version with this commit sha so we are testing exactly this verison.
sed -ri "s|'(quay.io/reactiveops/polaris:).+'|'\1${CIRCLE_SHA1}'|" ./deploy/webhook.yaml

function check_webhook_is_ready() {
  echo "Waiting for webhook to be ready"
  # Get the epoch time in one minute from now
  local timeout_epoch=$(date -d "+1 minute" +%s)
  # loop until this fails (desired condition is we cannot apply this yaml doc, which means the webhook is working
  while kubectl apply -f failing_test.deployment.yaml; do
    if [[ "$(date +%s)" -ge "${timeout_epoch}" ]]; then
      echo -e "Timeout hit waiting for webhook readiness: exiting"
      exit 1
    fi
    echo -n "."
    kubectl -n polaris get po -oyaml
    kubectl -n polaris logs --tail 10 -l app=polaris
    sleep 0.5
  done
  # clean up the test (the "or true" is to catch the condition that it couldn't delete something
  kubectl delete -f failing_test.deployment.yaml || true
  echo "Webhook started!"
}

# Install the webhook
kubectl apply -f ./deploy/webhook.yaml &> /dev/null

# wait for the webhook to come online
check_webhook_is_ready

# Run the tests
# Webhook started, setting all tests as passed initially.
ALL_TESTS_PASSED=1

for filename in test/passing_test.*.yaml; do
    echo $filename
    if ! kubectl apply -f $filename &> /dev/null; then
        ALL_TESTS_PASSED=0
        echo "Test Failed: Polaris prevented a deployment with no configuration issues." 
    fi
done
for filename in test/failing_test.*.yaml; do
    echo $filename
    if kubectl apply -f $filename &> /dev/null; then
        ALL_TESTS_PASSED=0
        echo "Test Failed: Polaris should have prevented this deployment due to configuration issues."
    fi
done

#Verify that all the tests passed.
if [ $ALL_TESTS_PASSED -eq 1 ]; then
    echo "Tests Passed."
else
    echo "Tests Failed."
    exit 1
fi
