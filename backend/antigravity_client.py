import os
import json
import uuid
import time
import logging
import requests
from typing import Dict, Any, List
from datetime import datetime

# Configure standard logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class AntigravityClient:
    """
    Client wrapper for the Google Antigravity REST API.
    Currently implements realistic mocking for crisis response orchestration,
    structured for seamless swap to the live API endpoint.
    """

    def __init__(self, api_key: str = "MOCK_KEY", log_file: str = "antigravity_logs.json"):
        """
        Initializes the Antigravity client.

        Args:
            api_key (str): The API key for Google Antigravity.
            log_file (str): Local file path for logging request traces.
        """
        self.api_url = "https://api.antigravity.google.com/v1/plan"
        self.api_key = api_key
        self.log_file = log_file
        self.max_retries = 3

        # Ensure log file exists with an empty list if it doesn't
        if not os.path.exists(self.log_file):
            with open(self.log_file, 'w') as f:
                json.dump([], f)

    def _log_trace(self, request_data: Dict[str, Any], response_data: Dict[str, Any]) -> None:
        """
        Appends the request and response trace to the local JSON log file.

        Args:
            request_data (Dict[str, Any]): The payload sent to the API.
            response_data (Dict[str, Any]): The response returned from the API.
        """
        trace = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "request": request_data,
            "response": response_data
        }
        try:
            # Read existing
            with open(self.log_file, 'r') as f:
                logs = json.load(f)
            # Append new
            logs.append(trace)
            # Write back
            with open(self.log_file, 'w') as f:
                json.dump(logs, f, indent=4)
        except Exception as e:
            logger.error(f"Failed to write to {self.log_file}: {e}")

    def _generate_mock_response(self, context: Dict[str, Any]) -> Dict[str, Any]:
        """
        Generates a realistic mock response based on the crisis context,
        including realistic multi-agent traces (Observer, Analyst, Decider, Executor, Evaluator).

        Args:
            context (Dict[str, Any]): The crisis context dictionary containing signals.

        Returns:
            Dict[str, Any]: The mock Antigravity planning response with agent traces.
        """
        # mock: simulation variables based on incoming signals
        crisis_type = context.get("crisis_type", "unknown").lower()
        severity = context.get("severity", 0.5)
        location = context.get("location", "Unknown Location")
        social = context.get("social_text", "")
        test_mode = context.get("test_mode", False) or (context.get("test_mode_active") is True)

        trace_id = str(uuid.uuid4())
        timestamp_str = datetime.now().isoformat()

        # Base templates
        response = {
            "antigravity_trace_id": trace_id,
            "workplan": ["classify", "allocate", "simulate", "notify"],
            "tool_calls": ["weather_api", "traffic_api", "social_sentiment_api"],
            "reasoning": f"Analyzed {crisis_type} event at {location} with severity {severity:.2f}.",
            "final_decision": "monitor_situation",
            "allocation_plan": {},
            "simulation": {"eta_reduction_minutes": 0, "traffic_reroute": False, "side_effects": "None"},
            "notifications": [],
            "traces": []
        }

        # Handle false alarm / low confidence escalation case
        is_low_confidence = severity < 0.40

        if is_low_confidence:
            response["reasoning"] += " Low confidence detected. Holding allocation for commander verification."
            response["final_decision"] = "await_verification"
            response["allocation_plan"] = {}
            response["simulation"] = {
                "eta_reduction_minutes": 0,
                "traffic_reroute": False,
                "side_effects": "No resources dispatched due to low confidence."
            }
            response["notifications"] = [
                {"target": "command_center", "message": f"⚠️ Escalate: Low confidence signal at {location}. Verification required."}
            ]
        elif crisis_type == "fire":
            if severity > 0.7 or "smoke" in social.lower():
                response["reasoning"] += " High risk of spread detected. Immediate intervention required."
                response["final_decision"] = "evacuate_and_dispatch_heavy_units"
                response["allocation_plan"] = {"fire_trucks": 4, "ambulances": 2, "police": 3}
                response["simulation"] = {
                    "eta_reduction_minutes": 15,
                    "traffic_reroute": True,
                    "side_effects": "Heavy congestion on outbound arterial routes."
                }
                response["notifications"] = [
                    {"target": "public", "message": f"EMERGENCY: Evacuate {location} immediately due to severe fire."},
                    {"target": "hospital", "message": "Prepare burn unit; inbound casualties possible."},
                    {"target": "utility", "message": "Shut down gas mains in sectors adjacent to fire."}
                ]
            else:
                response["final_decision"] = "dispatch_scout_unit"
                response["allocation_plan"] = {"fire_trucks": 1}
                response["simulation"] = {
                    "eta_reduction_minutes": 5,
                    "traffic_reroute": False,
                    "side_effects": "Normal flow maintained."
                }
                response["notifications"] = [{"target": "public", "message": f"Fire reported at {location}. Please avoid the area."}]

        elif crisis_type == "flood":
            if severity > 0.6:
                response["final_decision"] = "deploy_swift_water_rescue_and_block_roads"
                response["allocation_plan"] = {"rescue_boats": 2, "police": 4, "ambulances": 1}
                response["simulation"] = {
                    "eta_reduction_minutes": 20,
                    "traffic_reroute": True,
                    "side_effects": "Minor delays expected on elevated bypasses."
                }
                response["notifications"] = [
                    {"target": "public", "message": f"WARNING: Flash flood in {location}. Do not drive through standing water."},
                    {"target": "utility", "message": "De-energize ground-level transformers in flood zone."}
                ]
            else:
                response["final_decision"] = "dispatch_scout_unit"
                response["allocation_plan"] = {"police": 1}
                response["simulation"] = {
                    "eta_reduction_minutes": 3,
                    "traffic_reroute": False,
                    "side_effects": "None"
                }
                response["notifications"] = [{"target": "public", "message": f"Minor flooding reported at {location}. Use caution."}]
        else:
            # Fallback/Unknown
            response["final_decision"] = "dispatch_scout_unit"
            response["allocation_plan"] = {"police": 1}
            response["notifications"] = [{"target": "public", "message": f"Incident reported at {location}."}]

        # Construct multi-agent traces (Observer, Analyst, Decider, Executor, Evaluator)
        # Observer Agent
        obs_conf_before = 0.5
        obs_conf_after = 0.85 if not is_low_confidence else 0.35
        obs_reasoning = (
            f"Observer scanned visual feed and social text. "
            f"Detected crisis keywords and YOLO confidence of {severity:.2f}."
        )
        if is_low_confidence:
            obs_reasoning = f"Observer scanned visual feed. Conflicting or very weak signals detected (Conf: {severity:.2f})."

        observer_trace = {
            "agent_name": "Observer",
            "step_type": "OBSERVE",
            "reasoning": obs_reasoning,
            "inputs": {
                "social_text": social,
                "location": location,
                "yolo_severity": context.get("severity")
            },
            "output": {
                "signals_fused": not is_low_confidence,
                "raw_risk": severity
            },
            "confidence_before": obs_conf_before,
            "confidence_after": obs_conf_after,
            "tool_calls": [
                {"tool_name": "yolo_detector", "arguments": {"image": "uploaded_frame.jpg"}},
                {"tool_name": "social_analyzer", "arguments": {"query": social}}
            ],
            "duration_ms": 110,
            "timestamp": timestamp_str
        }

        # Analyst Agent
        an_conf_before = obs_conf_after
        an_conf_after = 0.90 if not is_low_confidence else 0.38
        an_reasoning = (
            f"Analyst correlated location weather ({context.get('weather', {}).get('condition', 'dry')}) "
            f"and traffic ({context.get('traffic', {}).get('congestion', 'normal')}) with visual alert. "
            f"Wind and traffic conditions analysis completed."
        )
        if is_low_confidence:
            an_reasoning = "Analyst verified sensor anomalies. High risk of false positive due to conflicting sensor readings."

        analyst_trace = {
            "agent_name": "Analyst",
            "step_type": "ANALYZE",
            "reasoning": an_reasoning,
            "inputs": {
                "weather": context.get("weather"),
                "traffic": context.get("traffic"),
                "base_confidence": obs_conf_after
            },
            "output": {
                "weather_influence": "aggravating" if context.get("weather", {}).get("wind_kmh", 0) > 20 else "neutral",
                "traffic_bottleneck": "high" if context.get("traffic", {}).get("congestion") == "high" else "low"
            },
            "confidence_before": an_conf_before,
            "confidence_after": an_conf_after,
            "tool_calls": [
                {"tool_name": "weather_api", "arguments": {"location": location}},
                {"tool_name": "traffic_api", "arguments": {"location": location}}
            ],
            "duration_ms": 195,
            "timestamp": timestamp_str
        }

        # Decider Agent
        dec_conf_before = an_conf_after
        dec_conf_after = 0.95 if not is_low_confidence else 0.40
        dec_reasoning = (
            f"Decider evaluated critical response criteria. Crisis type '{crisis_type}' "
            f"with severity {severity:.2f} warrants final decision: '{response['final_decision']}'."
        )
        if is_low_confidence:
            dec_reasoning = "Decider determined that automatic action is unsafe. Flagging for commander verification."

        decider_trace = {
            "agent_name": "Decider",
            "step_type": "DECIDE",
            "reasoning": dec_reasoning,
            "inputs": {
                "fused_risk": severity,
                "analyst_confidence": an_conf_after
            },
            "output": {
                "decision": response["final_decision"],
                "requires_review": is_low_confidence
            },
            "confidence_before": dec_conf_before,
            "confidence_after": dec_conf_after,
            "tool_calls": [],
            "duration_ms": 85,
            "timestamp": timestamp_str
        }

        # Executor Agent
        exec_conf_before = dec_conf_after
        exec_conf_after = 0.97 if not is_low_confidence else 0.42
        exec_reasoning = (
            f"Executor initiated resource allocation for {response['allocation_plan']}. "
            f"Dispatched {len(response['notifications'])} response broadcasts."
        )
        if is_low_confidence:
            exec_reasoning = "Executor halted dispatch. Sending notification to Command Center dashboard only."

        executor_trace = {
            "agent_name": "Executor",
            "step_type": "EXECUTE",
            "reasoning": exec_reasoning,
            "inputs": {
                "allocation_plan": response["allocation_plan"],
                "notifications": response["notifications"]
            },
            "output": {
                "dispatch_status": "dispatched" if not is_low_confidence else "on_hold",
                "sent_alerts": len(response["notifications"])
            },
            "confidence_before": exec_conf_before,
            "confidence_after": exec_conf_after,
            "tool_calls": [
                {"tool_name": "resource_dispatcher", "arguments": response["allocation_plan"]},
                {"tool_name": "broadcast_manager", "arguments": {"notifications": response["notifications"]}}
            ],
            "duration_ms": 140,
            "timestamp": timestamp_str
        }

        # Evaluator Agent
        eval_conf_before = exec_conf_after
        eval_conf_after = 0.99 if not is_low_confidence else 0.45
        eval_reasoning = (
            f"Evaluator completed predictive simulation of the dispatch execution. "
            f"ETA reduction: {response['simulation'].get('eta_reduction_minutes')} min. Side effects: {response['simulation'].get('side_effects')}."
        )
        if is_low_confidence:
            eval_reasoning = "Evaluator validated stand-by status. No immediate side effects expected."

        evaluator_trace = {
            "agent_name": "Evaluator",
            "step_type": "EVALUATE",
            "reasoning": eval_reasoning,
            "inputs": {
                "simulation_context": response["simulation"],
                "last_step_confidence": exec_conf_after
            },
            "output": {
                "simulation_success": True,
                "network_stability_index": 0.94 if not is_low_confidence else 1.00
            },
            "confidence_before": eval_conf_before,
            "confidence_after": eval_conf_after,
            "tool_calls": [
                {"tool_name": "simulator_engine", "arguments": response["simulation"]}
            ],
            "duration_ms": 220,
            "timestamp": timestamp_str
        }

        # Combine all traces
        response["traces"] = [
            observer_trace,
            analyst_trace,
            decider_trace,
            executor_trace,
            evaluator_trace
        ]

        return response

    def plan(self, crisis_context: Dict[str, Any]) -> Dict[str, Any]:
        """
        Orchestrates crisis reasoning by calling the Google Antigravity API.
        Includes retry logic for network resilience.

        Args:
            crisis_context (Dict[str, Any]): Context metadata of the crisis signal.

        Returns:
            Dict[str, Any]: The orchestration plan along with multi-agent traces.
        """
        logger.info(f"Initiating Antigravity plan for crisis: {crisis_context.get('crisis_type')}")

        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json"
        }

        payload = {"context": crisis_context}

        # Simulation / Request Loop
        for attempt in range(1, self.max_retries + 1):
            try:
                # -----------------------------------------------------------------
                # REAL API CALL (Commented out for mock mode)
                # response = requests.post(self.api_url, json=payload, headers=headers, timeout=10)
                # response.raise_for_status()
                # data = response.json()
                # -----------------------------------------------------------------

                # MOCK MODE
                time.sleep(0.5)  # Simulate network latency
                data = self._generate_mock_response(crisis_context)

                # Log success
                self._log_trace(request_data=payload, response_data=data)
                logger.info(f"Antigravity plan generated successfully (Trace ID: {data['antigravity_trace_id']}).")
                return data

            except requests.exceptions.RequestException as e:
                logger.warning(f"Antigravity API request failed (Attempt {attempt}/{self.max_retries}): {e}")
                if attempt == self.max_retries:
                    logger.error("Max retries reached. Falling back to safe defaults.")
                    fallback_data = {
                        "antigravity_trace_id": str(uuid.uuid4()),
                        "error": str(e),
                        "workplan": ["fallback_monitor"],
                        "reasoning": "Failed to reach Antigravity backend. Falling back to local monitoring.",
                        "allocation_plan": {},
                        "simulation": {},
                        "notifications": [],
                        "traces": []
                    }
                    self._log_trace(request_data=payload, response_data=fallback_data)
                    return fallback_data
                time.sleep(2 ** attempt) # Exponential backoff


# --- Instantiate a global client to be imported by main.py ---
client = AntigravityClient()

# Expose a direct function for easy importing in main.py
def plan(crisis_context: Dict[str, Any]) -> Dict[str, Any]:
    """
    Convenience wrapper function for AntigravityClient.plan.

    Args:
        crisis_context (Dict[str, Any]): Context metadata of the crisis signal.

    Returns:
        Dict[str, Any]: The orchestration plan along with multi-agent traces.
    """
    return client.plan(crisis_context)


if __name__ == "__main__":
    # Test execution guard
    print("=== Testing Antigravity Client ===")

    test_context = {
        "crisis_type": "fire",
        "severity": 0.85,
        "location": "G-10, Islamabad",
        "weather": {"condition": "dry", "wind_kmh": 25},
        "traffic": {"congestion": "high", "speed_kmh": 12},
        "social_text": "Massive smoke plumes visible from the highway!"
    }

    result = plan(test_context)

    print("\n--- Antigravity Output ---")
    print(json.dumps(result, indent=2))

    print("\nCheck 'antigravity_logs.json' to verify the trace was appended.")