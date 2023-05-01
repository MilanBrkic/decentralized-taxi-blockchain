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
  adminInterfereStart: Fun([], Null),
};

const computeStartRideResults = (
  passengerStart,
  driverStart,
  adminInterference,
  timeoutDetected
) => {
  if (passengerStart && driverStart) {
    return {
      shouldContinue: true,
      punishPassenger: false,
      punishDriver: false,
    };
  } else {
    if (timeoutDetected || adminInterference) {
      return {
        shouldContinue: false,
        punishPassenger: false,
        punishDriver: false,
      };
    } else {
      return {
        shouldContinue: false,
        punishPassenger: false,
        punishDriver: false,
      };
    }
  }
};

export const main = Reach.App(() => {
  const Admin = Participant("Admin", adminInteract);
  const Passenger = Participant("Passenger", passengerInteract);
  const Driver = Participant("Driver", driverInteract);
  const Ride = API("Ride", rideInteract);

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

  const [passengerStart, driverStart, adminInterfered, timeoutDetected] =
    parallelReduce([false, false, false, false])
      .invariant(balance() == passengerPrice + deposit * 2)
      .while(
        (!passengerStart || !driverStart) &&
          !timeoutDetected &&
          !adminInterfered
      )
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
              return [true, driverStart, adminInterfered, timeoutDetected];
            } else {
              return [passengerStart, true, adminInterfered, timeoutDetected];
            }
          },
        ];
      })
      .api_(Ride.adminInterfereStart, () => {
        check(this === Admin, "only an admin can interfere");
        return [
          0,
          (ret) => {
            ret(null);
            Driver.interact.log("Admin detected.");
            return [passengerStart, driverStart, true, timeoutDetected];
          },
        ];
      })
      .timeout(absoluteTime(1000), () => {
        Driver.publish();
        Driver.interact.log("Timeout detected.");
        return [passengerStart, driverStart, adminInterfered, true];
      });

  const startResults = computeStartRideResults(
    passengerStart,
    driverStart,
    adminInterfered,
    timeoutDetected
  );

  if (startResults.shouldContinue) {
    Driver.interact.log("BC: continues ride");
    transfer(passengerPrice - fee + deposit).to(Driver);
    transfer(deposit).to(Passenger);
    transfer(fee).to(Admin);
  } else {
    Driver.interact.log("BC: does not");
    transfer(passengerPrice + deposit).to(Passenger);
    transfer(deposit).to(Driver);
  }

  commit();

  exit();
});
