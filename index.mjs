import { loadStdlib, test } from "@reach-sh/stdlib";
import * as backend from "./build/index.main.mjs";
const stdlib = loadStdlib(process.env);

const STARTING_BALANCE = stdlib.parseCurrency(1000);
const STARTING_BALANCE_NUMBER = Number(STARTING_BALANCE);
const FEE_PERCENTAGE = 2;
const DEPOSIT_PERCENTAGE = 30;
const RIDE_PRICE = stdlib.parseCurrency(100);
const RIDE_PRICE_NUMBER = Number(RIDE_PRICE);

const suStr = stdlib.standardUnit;
const auStr = stdlib.atomicUnit;
const toAU = (su) => stdlib.parseCurrency(su);
const toSU = (au) => stdlib.formatCurrency(au, 4);
const showBalance = async (acc) =>
  console.log(
    `Balance for ${acc.networkAccount.addr} is ${toSU(
      await stdlib.balanceOf(acc)
    )} ${suStr}.`
  );

const showBalances = async (accs) => {
  for (const acc of accs) {
    await showBalance(acc);
  }
};

const startRide = async (address, contractInfo) => {
  const contract = address.contract(backend, contractInfo);
  await contract.a.Ride.start();
};

const endRide = async (address, contractInfo) => {
  const contract = address.contract(backend, contractInfo);
  await contract.a.Ride.end();
};

const adminInterfereStart = async (address, contractInfo) => {
  const contract = address.contract(backend, contractInfo);
  await contract.a.Ride.start();
};

const adminInterfereEnd = async (
  address,
  contractInfo,
  wasPassengerAtLocation,
  wasDriverAtLocation
) => {
  const contract = address.contract(backend, contractInfo);
  await contract.a.Ride.adminInterfereEnd(
    wasPassengerAtLocation,
    wasDriverAtLocation
  );
};

const adminInteract = {
  ...stdlib.hasConsoleLogger,
  feePercentage: FEE_PERCENTAGE,
  depositPercentage: DEPOSIT_PERCENTAGE,
  ready: () => {
    console.log("contract deployed");

    throw 666;
  },
};

const informTimeout = () => {
  console.log(`timed out.`);
};

const createAccounts = async () => {
  const adminAcc = await stdlib.newTestAccount(STARTING_BALANCE);
  const passengerAcc = await stdlib.newTestAccount(STARTING_BALANCE);
  const driverAcc = await stdlib.newTestAccount(STARTING_BALANCE);

  const adminCtc = adminAcc.contract(backend);
  const contractInfo = adminCtc.getInfo();
  const passengerCtc = passengerAcc.contract(backend, contractInfo);
  const driverCtc = driverAcc.contract(backend, contractInfo);

  try {
    await Promise.all([
      adminCtc.participants.Admin(adminInteract),
      passengerCtc.participants.Passenger({
        ...stdlib.hasConsoleLogger,
        passengerPrice: RIDE_PRICE,
        informTimeout,
      }),
      driverCtc.participants.Driver({
        ...stdlib.hasConsoleLogger,
        driverPrice: RIDE_PRICE,
        informTimeout,
      }),
    ]);
  } catch (error) {
    if (error !== 666) {
      throw error;
    }
  }

  return { adminAcc, passengerAcc, driverAcc, contractInfo };
};

const oneToken = stdlib.parseCurrency(1);
const oneTokenNumber = Number(oneToken);
test.one("ride successful", async () => {
  const { adminAcc, passengerAcc, driverAcc, contractInfo } =
    await createAccounts();

  await startRide(passengerAcc, contractInfo);
  await startRide(driverAcc, contractInfo);

  await endRide(passengerAcc, contractInfo);
  await endRide(driverAcc, contractInfo);

  const adminBalance = Number(await stdlib.balanceOf(adminAcc));
  const passengerBalance = Number(await stdlib.balanceOf(passengerAcc));
  const driverBalance = Number(await stdlib.balanceOf(driverAcc));

  test.chk(
    "admin should be paid the fee ",
    adminBalance - (RIDE_PRICE_NUMBER * FEE_PERCENTAGE) / 100 + oneTokenNumber >
      STARTING_BALANCE_NUMBER,
    true
  );

  test.chk(
    "passenger should be charged for the ride ",
    passengerBalance + RIDE_PRICE_NUMBER + oneTokenNumber >
      STARTING_BALANCE_NUMBER &&
      passengerBalance + oneTokenNumber < STARTING_BALANCE_NUMBER,
    true
  );

  test.chk(
    "driver should be paid the ride ",
    driverBalance -
      RIDE_PRICE_NUMBER +
      (RIDE_PRICE_NUMBER * FEE_PERCENTAGE) / 100 +
      oneTokenNumber >
      STARTING_BALANCE_NUMBER,
    true
  );
});

test.one(
  "Ride is cancelled, because passenger did not start the ride",
  async () => {
    const { adminAcc, passengerAcc, driverAcc, contractInfo } =
      await createAccounts();

    await startRide(passengerAcc, contractInfo);
    await adminInterfereStart(adminAcc, contractInfo);

    const adminBalance = Number(await stdlib.balanceOf(adminAcc));
    const passengerBalance = Number(await stdlib.balanceOf(passengerAcc));
    const driverBalance = Number(await stdlib.balanceOf(driverAcc));

    test.chk(
      "adminBalance should be unchanged",
      adminBalance + oneTokenNumber > STARTING_BALANCE_NUMBER &&
        adminBalance < STARTING_BALANCE_NUMBER,
      true
    );

    test.chk(
      "passengerBalance should be unchanged",
      passengerBalance + oneTokenNumber > STARTING_BALANCE_NUMBER &&
        passengerBalance < STARTING_BALANCE_NUMBER,
      true
    );

    test.chk(
      "driverBalance should be unchanged",
      driverBalance + oneTokenNumber > STARTING_BALANCE_NUMBER &&
        driverBalance < STARTING_BALANCE_NUMBER,
      true
    );
  }
);

test.one("call the apis before the preferred state, endRide", async () => {
  const { passengerAcc, contractInfo } = await createAccounts();

  let didError = false;
  try {
    await endRide(passengerAcc, contractInfo);
    didError = false;
  } catch (error) {
    didError = true;
  }

  test.chk("should error", didError, true);
});

test.one(
  "call the apis before the preferred state, adminInterfereEnd",
  async () => {
    const { adminAcc, contractInfo } = await createAccounts();

    let didError = false;
    try {
      await adminInterfereEnd(adminAcc, contractInfo);
      didError = false;
    } catch (error) {
      didError = true;
    }

    test.chk("should error", didError, true);
  }
);

test.one("passenger call the admin endpoint", async () => {
  const { passengerAcc, driverAcc, contractInfo } = await createAccounts();

  await startRide(passengerAcc, contractInfo);
  await startRide(driverAcc, contractInfo);

  let didError = false;
  try {
    await adminInterfereEnd(passengerAcc, contractInfo);
    didError = false;
  } catch (error) {
    didError = true;
  }

  test.chk("should error", didError, true);
});

await test.run();
