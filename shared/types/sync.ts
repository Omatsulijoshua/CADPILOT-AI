export interface SyncMutation<TPayload extends object = object> {
  mutationId: string;
  projectId: string;
  baseRevision: number;
  createdAt: string;
  contentHash: string;
  payload: TPayload;
}
