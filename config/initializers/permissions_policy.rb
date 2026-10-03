# Browser features the app never uses are switched off for every page (and for anything
# that might get injected into one).
Rails.application.config.permissions_policy do |policy|
  policy.camera :none
  policy.microphone :none
  policy.geolocation :none
  policy.usb :none
  policy.payment :none
  policy.gyroscope :none
end
