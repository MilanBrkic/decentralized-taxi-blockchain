"reach 0.1";

const logInteract = {
  log: Fun(true, Null),
};

const userInteract = {
  informTimeout: Fun([], Null),
};

const passengerInteract = {
  ...logInteract,
  ...userInteract,
  passengerPrice: UInt,
};

const driverInteract = {
  ...logInteract,
  ...userInteract,
  driverPrice: UInt,
};

const adminInteract = {
  ...logInteract,
  ready: Fun([], Null),
  feePercentage: UInt,
  depositPercentage: UInt,
};

const rideInteract = {
  start: Fun([], Null),
  end: Fun([], Null),
  adminInterfereEnd: Fun([Bool, Bool], Null),
};

const notifyInteract = {
  rideStarted: [Address, Address, UInt],
  rideEnded: [UInt, UInt, UInt],
  adminInterfereOnStartRide: [],
  adminInterferenceOnEndRide: [Bool, Bool],
};

const shouldTheRideContinue = (passengerStart, driverStart) => {
  if (passengerStart && driverStart) {
    return true;
  } else {
    return false;
  }
};

const computeEndRideResults = (
  passengerEnd,
  driverEnd,
  wasPassengerAtLocation,
  wasDriverAtLocation,
  ridePrice,
  deposit,
  fee
) => {
  if (passengerEnd && driverEnd) {
    // all good
    return {
      passenger: deposit,
      driver: ridePrice + deposit - fee,
      admin: fee,
    };
  } else if (passengerEnd) {
    // the ride is charged and the driver is punished
    return {
      passenger: deposit,
      driver: ridePrice - fee,
      admin: fee + deposit,
    };
  } else if (driverEnd) {
    if (wasPassengerAtLocation && wasDriverAtLocation) {
      // the ride is charged and the passenger is punished
      return {
        passenger: 0,
        driver: ridePrice + deposit - fee,
        admin: fee + deposit,
      };
    } else if (!wasPassengerAtLocation && !wasDriverAtLocation) {
      // the driver is punished because he lied
      return {
        passenger: ridePrice + deposit,
        driver: 0,
        admin: deposit,
      };
    } else {
      // all tokens are returned
      return {
        passenger: ridePrice + deposit,
        driver: deposit,
        admin: 0,
      };
    }
  } else {
    if (wasPassengerAtLocation && wasDriverAtLocation) {
      // the ride is charged and both participants are punished
      return {
        passenger: 0,
        driver: ridePrice - fee,
        admin: fee + 2 * deposit,
      };
    } else {
      // the ride does not get charged and both participants are punished
      return {
        passenger: ridePrice,
        driver: 0,
        admin: 2 * deposit,
      };
    }
  }
};

export const main = Reach.App(() => {
  const Admin = Participant("Admin", adminInteract);
  const Passenger = Participant("Passenger", passengerInteract);
  const Driver = Participant("Driver", driverInteract);
  const Ride = API("Ride", rideInteract);
  const Notify = Events(notifyInteract);

  init();
  const informTimeout = () => {
    each([Passenger, Driver], () => {
      interact.informTimeout();
    });
  };

  // Admin init
  Admin.only(() => {
    const feePercentage = declassify(interact.feePercentage);
    check(
      feePercentage >= 0 && feePercentage <= 100,
      "feePercentage must be non-negative"
    );
    const depositPercentage = declassify(interact.depositPercentage);
    check(
      depositPercentage >= 0 && depositPercentage <= 100,
      "depositPercentage must be non-negative"
    );
  });
  Admin.publish(feePercentage, depositPercentage);

  commit();

  // Passenger init
  Passenger.only(() => {
    const passengerPrice = declassify(interact.passengerPrice);
    check(passengerPrice >= 0, "passengerPrice must be non-negative");
  });
  Passenger.publish(passengerPrice).pay(
    passengerPrice + (passengerPrice * depositPercentage) / 100
  );
  const deposit = (passengerPrice * depositPercentage) / 100;
  const fee = (passengerPrice * feePercentage) / 100;

  commit();

  // Driver init
  Driver.only(() => {
    const driverPrice = declassify(interact.driverPrice);
    check(driverPrice >= 0, "driverPrice must be non-negative");
    check(
      driverPrice === passengerPrice,
      "driverPrice must be equal to passengerPrice"
    );
  });
  Driver.publish(driverPrice)
    .pay(deposit)
    .timeout(relativeTime(1000), () => {
      closeTo(Passenger, informTimeout);
    });

  Admin.interact.ready();

  const [passengerStart, driverStart, shouldStop] = parallelReduce([
    false,
    false,
    false,
  ])
    .invariant(balance() == passengerPrice + deposit * 2)
    .while((!passengerStart || !driverStart) && !shouldStop)
    .api_(Ride.start, () => {
      check(
        this === Passenger || this === Driver || this === Admin,
        "not a participant"
      );
      return [
        0,
        (ret) => {
          ret(null);
          if (this == Passenger) {
            return [true, driverStart, shouldStop];
          } else if (this == Driver) {
            return [passengerStart, true, shouldStop];
          } else {
            Notify.adminInterfereOnStartRide();
            return [passengerStart, driverStart, true];
          }
        },
      ];
    });

  const shouldContinue = shouldTheRideContinue(passengerStart, driverStart);

  if (!shouldContinue) {
    Driver.interact.log("BC: does not");
    transfer(passengerPrice + deposit).to(Passenger);
    transfer(deposit).to(Driver);
  } else {
    Notify.rideStarted(Passenger, Driver, passengerPrice);
    const [
      passengerEnd,
      driverEnd,
      wasPassengerAtLocation,
      wasDriverAtLocation,
      adminInterferedEnd,
    ] = parallelReduce([false, false, false, false, false])
      .invariant(balance() == passengerPrice + deposit * 2)
      .while((!passengerEnd || !driverEnd) && !adminInterferedEnd)
      .api_(Ride.end, () => {
        check(this === Passenger || this === Driver, "not a participant");
        return [
          0,
          (ret) => {
            ret(null);
            if (this == Passenger) {
              return [
                true,
                driverEnd,
                wasPassengerAtLocation,
                wasDriverAtLocation,
                adminInterferedEnd,
              ];
            } else {
              return [
                passengerEnd,
                true,
                wasPassengerAtLocation,
                wasDriverAtLocation,
                adminInterferedEnd,
              ];
            }
          },
        ];
      })
      .api_(Ride.adminInterfereEnd, (wasPAtLocation, wasDAtLocation) => {
        check(this === Admin, "only an admin can interfere");
        return [
          0,
          (ret) => {
            ret(null);
            Driver.interact.log("Admin detected on end ride.");
            return [
              passengerEnd,
              driverEnd,
              wasPAtLocation,
              wasDAtLocation,
              true,
            ];
          },
        ];
      });

    const endPayment = computeEndRideResults(
      passengerEnd,
      driverEnd,
      wasPassengerAtLocation,
      wasDriverAtLocation,
      passengerPrice,
      deposit,
      fee
    );

    Notify.rideEnded(endPayment.passenger, endPayment.driver, endPayment.admin);
    check(
      endPayment.passenger + endPayment.driver + endPayment.admin ==
        passengerPrice + 2 * deposit,
      "sum of payments must be equal to passengerPrice+deposit+fee"
    );

    transfer(endPayment.driver).to(Driver);
    transfer(endPayment.passenger).to(Passenger);
    transfer(endPayment.admin).to(Admin);
  }

  commit();
  exit();
});
