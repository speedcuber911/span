import { useEffect, useState } from "react";
import { Download, Share, Plus, X } from "lucide-react";
import { Button } from "@/components/ui/button";

// BeforeInstallPromptEvent (Chrome/Android) — typed loosely
interface BIPEvent extends Event {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: "accepted" | "dismissed" }>;
}

function isStandalone() {
  return (
    window.matchMedia?.("(display-mode: standalone)").matches ||
    // iOS Safari
    (window.navigator as unknown as { standalone?: boolean }).standalone === true
  );
}

function isIOS() {
  const ua = window.navigator.userAgent;
  if (/iphone|ipad|ipod/i.test(ua)) return true;
  // iPadOS 13+ Safari reports a desktop Mac UA — detect via touch points
  const isIPadOS =
    window.navigator.platform === "MacIntel" &&
    (window.navigator as unknown as { maxTouchPoints?: number }).maxTouchPoints! > 1;
  return isIPadOS;
}

export function InstallButton() {
  const [deferred, setDeferred] = useState<BIPEvent | null>(null);
  const [showIOS, setShowIOS] = useState(false);

  useEffect(() => {
    const onPrompt = (e: Event) => {
      e.preventDefault();
      setDeferred(e as BIPEvent);
    };
    window.addEventListener("beforeinstallprompt", onPrompt);
    return () => window.removeEventListener("beforeinstallprompt", onPrompt);
  }, []);

  if (isStandalone()) return null; // already installed

  // Android / desktop Chrome: native prompt available
  if (deferred) {
    return (
      <Button
        variant="outline"
        size="sm"
        onClick={async () => {
          await deferred.prompt();
          await deferred.userChoice;
          setDeferred(null);
        }}
        title="Install app"
      >
        <Download className="size-4" /> Install
      </Button>
    );
  }

  // iOS: no programmatic prompt — show instructions
  if (isIOS()) {
    return (
      <>
        <Button variant="outline" size="sm" onClick={() => setShowIOS(true)} title="Add to Home Screen">
          <Download className="size-4" /> <span className="hidden sm:inline">Add to Home Screen</span>
        </Button>
        {showIOS && (
          <div
            className="fixed inset-0 z-[100] bg-black/50 backdrop-blur-sm grid place-items-end sm:place-items-center p-4 animate-fade-in"
            onClick={() => setShowIOS(false)}
          >
            <div
              className="w-full max-w-sm rounded-2xl border bg-popover p-5 shadow-xl"
              onClick={(e) => e.stopPropagation()}
            >
              <div className="flex items-start justify-between">
                <div className="flex items-center gap-2.5">
                  <img src="/apple-touch-icon.png" alt="" className="size-10 rounded-xl" />
                  <div>
                    <div className="font-semibold leading-tight">Add to Home Screen</div>
                    <div className="text-xs text-muted-foreground">Install Health Trends on your iPhone or iPad</div>
                  </div>
                </div>
                <button onClick={() => setShowIOS(false)} className="text-muted-foreground hover:text-foreground p-1">
                  <X className="size-4" />
                </button>
              </div>
              <ol className="mt-4 space-y-3 text-sm">
                <li className="flex items-center gap-3">
                  <span className="grid place-items-center size-7 rounded-full bg-secondary text-foreground font-semibold text-xs shrink-0">1</span>
                  <span className="flex items-center gap-1.5 flex-wrap">
                    Tap the <Share className="size-4 inline text-low" /> <b>Share</b> button in Safari's toolbar
                  </span>
                </li>
                <li className="flex items-center gap-3">
                  <span className="grid place-items-center size-7 rounded-full bg-secondary text-foreground font-semibold text-xs shrink-0">2</span>
                  <span className="flex items-center gap-1.5 flex-wrap">
                    Choose <Plus className="size-4 inline" /> <b>Add to Home Screen</b>
                  </span>
                </li>
                <li className="flex items-center gap-3">
                  <span className="grid place-items-center size-7 rounded-full bg-secondary text-foreground font-semibold text-xs shrink-0">3</span>
                  <span>Tap <b>Add</b> — it opens like a native app, even offline.</span>
                </li>
              </ol>
            </div>
          </div>
        )}
      </>
    );
  }

  return null;
}
