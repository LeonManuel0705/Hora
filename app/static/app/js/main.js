import { initShell } from "./shell.js";
import { initHome } from "./home.js";
import { initTasks } from "./tasks.js";

initShell();
initHome();
initTasks();

const pageModule = document.querySelector("[data-page-module]")?.dataset.pageModule;
if (pageModule) (await import(`./pages/${pageModule}.js`)).init?.();
