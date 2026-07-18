export type CallStatus =
  | "idle"
  | "incoming"
  | "outgoing"
  | "connecting"
  | "active";

export type CallDirection = "incoming" | "outgoing";
export type CallMediaType = "audio" | "video";

export interface CallPeer {
  id: string;
  displayName: string;
  avatarUrl?: string | null;
}

export interface StartCallPayload {
  calleeId: string;
  conversationId: string;
  mediaType: CallMediaType;
}

export interface IncomingCallPayload {
  callId: string;
  conversationId: string;
  caller: CallPeer;
  mediaType: CallMediaType;
  createdAt: string;
  timeoutMs: number;
}

export interface AcceptedCallPayload {
  callId: string;
  acceptedAt: string;
  mediaType: CallMediaType;
}

export interface EndedCallPayload {
  callId: string;
  conversationId?: string;
  reason: string;
  mediaType: CallMediaType;
  durationSeconds: number;
}

export interface SessionDescriptionSignal {
  type: "offer" | "answer";
  sdp: string;
}

export interface IceCandidateSignal {
  type: "ice-candidate";
  candidate: string;
  sdpMid?: string | null;
  sdpMLineIndex?: number | null;
}

export type CallSignal = SessionDescriptionSignal | IceCandidateSignal;

export interface CallSignalPayload {
  callId: string;
  signal: CallSignal;
}

export interface CallErrorDetails {
  code: string;
  message: string;
}

export interface CallErrorAck {
  ok: false;
  error: CallErrorDetails;
}

export interface CallSuccessAck {
  ok: true;
}

export interface StartCallSuccessAck extends CallSuccessAck {
  callId: string;
  createdAt: string;
  timeoutMs: number;
  mediaType: CallMediaType;
}

export type CallAck = CallSuccessAck | CallErrorAck;
export type StartCallAck = StartCallSuccessAck | CallErrorAck;

export interface CallState {
  status: CallStatus;
  direction: CallDirection | null;
  callId: string | null;
  conversationId: string | null;
  peer: CallPeer | null;
  mediaType: CallMediaType;
  startedAt: number | null;
  muted: boolean;
  cameraEnabled: boolean;
  operationPending: boolean;
  error: string | null;
  localStream: MediaStream | null;
  remoteStream: MediaStream | null;

  startCall: (
    peer: CallPeer,
    conversationId: string,
    mediaType: CallMediaType
  ) => Promise<void>;
  acceptCall: () => Promise<void>;
  rejectCall: () => Promise<void>;
  cancelCall: () => Promise<void>;
  endCall: () => Promise<void>;
  toggleMute: () => void;
  toggleCamera: () => void;
  handleIncoming: (payload: unknown) => void;
  handleAccepted: (payload: unknown) => Promise<void>;
  handleEnded: (payload: unknown) => void;
  handleSignal: (payload: unknown) => void;
  handleSocketDisconnect: () => void;
}
