import { execFileSync } from "node:child_process"
import { homedir } from "node:os"
import { join } from "node:path"

type ContextEvent = {
  system: Array<{ type: "text"; text: string }>
}

type PluginContext = {
  session: {
    hook(name: "context", handler: (event: ContextEvent) => void): Promise<unknown>
  }
}

function readReminder(): string {
  try {
    return execFileSync(join(homedir(), ".config/agent-hooks/git-consent-reminder.sh"), ["text"], { encoding: "utf8" }).trim()
  } catch {
    return ""
  }
}

export default {
  id: "git-consent",

  async setup(ctx: PluginContext) {
    const reminder = readReminder()
    if (!reminder) return
    await ctx.session.hook("context", event => {
      event.system.push({ type: "text", text: reminder })
    })
  },
}
