import { LightningElement, api } from 'lwc';

// Stub: renders launcher copy that points users at the Einstein Copilot panel.
// Agentforce does not yet expose a public LWC for embedding a specific agent on
// an App Page; swap the body for it once Salesforce ships one. See
// developing-agentforce skill for the latest state of embeddable agent UI.
export default class FmTableauAgentChat extends LightningElement {
    @api agentApiName = 'FluentMetric_Tableau_Analyst';
}
