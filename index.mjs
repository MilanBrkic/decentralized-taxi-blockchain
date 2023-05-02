import { loadStdlib } from "@reach-sh/stdlib";
import * as backend from "./build/index.main.mjs";
const stdlib = loadStdlib(process.env);

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

const continueRide = async () => {
  await endRide(passengerAcc, contractInfo);
  await endRide(driverAcc, contractInfo);
  setTimeout(
    () =>
      adminInterfereEnd(adminAcc, contractInfo, true, true)
        .then(async () => {
          await showBalances([adminAcc, passengerAcc, driverAcc]);
        })
        .catch(async (err) => {
          await showBalances([adminAcc, passengerAcc, driverAcc]);
          console.log(
            `admin tried to interfere the start ride but it already happened: ${err}`
          );
        }),
    20 * 1000
  );
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
  feePercentage: 2,
  depositPercentage: 50,
  ready: () => {
    console.log("contract deployed");

    throw 666;
  },
};

const informTimeout = () => {
  console.log(`timed out.`);
};

const adminAcc = await stdlib.newTestAccount(stdlib.parseCurrency(1000));
console.log(`adminAcc: ${adminAcc.networkAccount.addr}`);
const passengerAcc = await stdlib.newTestAccount(stdlib.parseCurrency(1000));
const driverAcc = await stdlib.newTestAccount(stdlib.parseCurrency(1000));

const adminCtc = adminAcc.contract(backend);
const contractInfo = adminCtc.getInfo();
const passengerCtc = passengerAcc.contract(backend, contractInfo);
const driverCtc = driverAcc.contract(backend, contractInfo);
adminCtc.events.rideEnded.monitor((evt) => {
  console.log(
    `Ride ended event | Passenger: ${toSU(
      Number(evt.what[0]._hex)
    )} | Driver: ${toSU(Number(evt.what[1]._hex))} | Admin: ${toSU(
      Number(evt.what[2]._hex)
    )}`
  );
});

adminCtc.events.rideStarted.monitor((evt) => {
  console.log(
    `Ride started event | Passenger: ${evt.what[0]} | Driver: ${
      evt.what[1]
    } | Price: ${toSU(Number(evt.what[2]._hex))} `
  );
});

adminCtc.events.adminInterfereOnStartRide.monitor((evt) => {
  console.log("Admin interfere on start ride event: ");
});

adminCtc.events.timeOut.monitor(() => {
  if (evt.what[0]) {
    console.log("Time out event detected on start.");
  } else {
    console.log("Time out event detected on end.");
  }
});

await showBalances([adminAcc, passengerAcc, driverAcc]);

try {
  await Promise.all([
    adminCtc.participants.Admin(adminInteract),
    passengerCtc.participants.Passenger({
      ...stdlib.hasConsoleLogger,
      passengerPrice: stdlib.parseCurrency(100),
      informTimeout,
    }),
    driverCtc.participants.Driver({
      ...stdlib.hasConsoleLogger,
      driverPrice: stdlib.parseCurrency(100),
      informTimeout,
    }),
  ]);
} catch (error) {
  if (error !== 666) {
    throw error;
  }
}

await startRide(passengerAcc, contractInfo);
await startRide(driverAcc, contractInfo);

setTimeout(
  () =>
    adminInterfereStart(adminAcc, contractInfo)
      .then(async () => {
        await showBalances([adminAcc, passengerAcc, driverAcc]);
      })
      .catch(async (err) => {
        await continueRide();
        console.log(
          `admin tried to interfere the start ride but it already happened: ${err}`
        );
      }),
  10 * 1000
);
