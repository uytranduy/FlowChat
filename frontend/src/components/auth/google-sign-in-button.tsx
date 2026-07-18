import { useEffect, useRef, useState } from "react";

type GoogleCredentialResponse = { credential?: string };

declare global {
  interface Window {
    google?: {
      accounts: {
        id: {
          initialize: (options: {
            client_id: string;
            callback: (response: GoogleCredentialResponse) => void;
          }) => void;
          renderButton: (
            element: HTMLElement,
            options: Record<string, string | number | boolean>
          ) => void;
        };
      };
    };
  }
}

let googleScriptPromise: Promise<void> | null = null;

function loadGoogleScript() {
  if (window.google) return Promise.resolve();
  if (googleScriptPromise) return googleScriptPromise;

  googleScriptPromise = new Promise<void>((resolve, reject) => {
    const existing = document.querySelector<HTMLScriptElement>(
      'script[src="https://accounts.google.com/gsi/client"]'
    );
    if (existing) {
      existing.addEventListener("load", () => resolve(), { once: true });
      existing.addEventListener("error", () => reject(new Error("Google script error")), {
        once: true,
      });
      return;
    }

    const script = document.createElement("script");
    script.src = "https://accounts.google.com/gsi/client";
    script.async = true;
    script.defer = true;
    script.onload = () => resolve();
    script.onerror = () => reject(new Error("Không tải được Google Sign-In."));
    document.head.appendChild(script);
  });
  return googleScriptPromise;
}

interface GoogleSignInButtonProps {
  onCredential: (idToken: string) => void | Promise<void>;
  disabled?: boolean;
  label?: "signin_with" | "signup_with" | "continue_with";
}

export function GoogleSignInButton({
  onCredential,
  disabled = false,
  label = "continue_with",
}: GoogleSignInButtonProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const callbackRef = useRef(onCredential);
  const [error, setError] = useState<string | null>(null);
  callbackRef.current = onCredential;

  useEffect(() => {
    const clientId = import.meta.env.VITE_GOOGLE_WEB_CLIENT_ID?.trim();
    if (!clientId) {
      setError("Thiếu VITE_GOOGLE_WEB_CLIENT_ID");
      return;
    }

    let active = true;
    loadGoogleScript()
      .then(() => {
        if (!active || !window.google || !containerRef.current) return;
        window.google.accounts.id.initialize({
          client_id: clientId,
          callback: ({ credential }) => {
            if (credential) void callbackRef.current(credential);
          },
        });
        containerRef.current.replaceChildren();
        window.google.accounts.id.renderButton(containerRef.current, {
          type: "standard",
          theme: "outline",
          size: "large",
          text: label,
          shape: "rectangular",
          logo_alignment: "left",
          width: containerRef.current.clientWidth || 320,
        });
      })
      .catch(() => active && setError("Không tải được nút Google."));

    return () => {
      active = false;
    };
  }, [label]);

  if (error) {
    return <p className="text-center text-xs text-destructive">{error}</p>;
  }

  return (
    <div
      className={disabled ? "pointer-events-none opacity-60" : undefined}
      aria-disabled={disabled}
    >
      <div ref={containerRef} className="flex min-h-10 w-full justify-center" />
    </div>
  );
}
