"""
signal_fusion.py
----------------
Multi-source crisis signal fusion service for the CIRO Fire Crisis Response System.

Combines three independent signal sources:
  - image   : YOLO-based fire/smoke visual detection (weight 0.6)
  - weather : Mock weather API data for environmental risk scoring (weight 0.2)
  - social  : Keyword analysis of social-media / citizen text (weight 0.2)

Each source produces a normalised [0.0 – 1.0] crisis score that is weighted and
summed into a single `fused_score`.  The highest-scoring crisis type wins.
"""

from typing import Optional
from services.trace_logger import TraceLogger


# ---------------------------------------------------------------------------
# Keyword lists per crisis type (Urdu + English, following rule-15 mock pattern)
# ---------------------------------------------------------------------------
CRISIS_KEYWORDS: dict[str, list[str]] = {
    "flood": [
        "flood", "flooding", "water", "rain", "bhar gaya", "pani",
        "barish", "overflowing", "inundated", "sehla",
    ],
    "fire": [
        "fire", "ag", "aag", "blaze", "smoke", "dhuwan",
        "burning", "jal raha", "flames", "inferno",
    ],
    "heatwave": [
        "heat", "garami", "garmi", "looo", "loo", "heat stroke",
        "heatwave", "scorching", "boiling", "garam",
    ],
}


class SignalFusion:
    """
    Fuses image, weather, and social signals into a single crisis assessment.

    Attributes:
        sources (dict): Enabled state and weight for each signal source.
        logger  (TraceLogger): Shared trace logger instance.
    """

    def __init__(self) -> None:
        """Initialise source registry and trace logger."""
        self.sources: dict = {
            "image":   {"active": True, "weight": 0.6},
            "weather": {"active": True, "weight": 0.2},
            "social":  {"active": True, "weight": 0.2},
        }
        self.logger = TraceLogger()

    # ------------------------------------------------------------------
    # Weather signal
    # ------------------------------------------------------------------
    def get_weather_signal(self, location: Optional[str] = "Karachi") -> dict:
        """
        Return mock weather data and derive environmental risk flags.

        Args:
            location (str, optional): City/area name for the mock data label.

        Returns:
            dict: Weather readings plus boolean risk flags and a crisis_score.
        """
        # // mock: static weather data for Karachi summer peak conditions
        temperature: float = 42.0
        humidity: float    = 65.0
        rainfall_mm: float = 25.0

        heatwave_risk: bool = temperature > 40
        flood_risk: bool    = rainfall_mm > 20

        # Score: each active risk adds 0.5 to a max of 1.0
        crisis_score: float = min(
            (0.5 if heatwave_risk else 0.0) + (0.5 if flood_risk else 0.0),
            1.0,
        )

        # Determine dominant crisis type from weather
        if flood_risk and heatwave_risk:
            crisis_type = "flood"          # flood takes priority (immediate danger)
        elif flood_risk:
            crisis_type = "flood"
        elif heatwave_risk:
            crisis_type = "heatwave"
        else:
            crisis_type = "none"

        self.logger.write_trace(
            agent_name="signal_fusion.weather",
            step_type="OBSERVE",
            reasoning=(
                f"Weather @ {location}: temp={temperature}°C, rain={rainfall_mm}mm "
                f"→ heatwave_risk={heatwave_risk}, flood_risk={flood_risk}"
            ),
            inputs={"location": location},
            output={
                "temperature": temperature,
                "humidity": humidity,
                "rainfall_mm": rainfall_mm,
                "heatwave_risk": heatwave_risk,
                "flood_risk": flood_risk,
                "crisis_type": crisis_type,
                "crisis_score": crisis_score,
            },
            confidence_before=0.5,
            confidence_after=crisis_score,
            tool_calls=[],
            duration_ms=5,
        )

        return {
            "location": location,
            "temperature": temperature,
            "humidity": humidity,
            "rainfall_mm": rainfall_mm,
            "heatwave_risk": heatwave_risk,
            "flood_risk": flood_risk,
            "crisis_type": crisis_type,
            "crisis_score": crisis_score,
        }

    # ------------------------------------------------------------------
    # Social / text signal
    # ------------------------------------------------------------------
    def get_social_signal(self, text_input: str) -> dict:
        """
        Scan citizen-reported text for crisis-type keywords and return a
        normalised confidence score.

        Args:
            text_input (str): Raw text (social media post, SMS alert, etc.).

        Returns:
            dict: Detected crisis type and a [0.0–1.0] confidence score.
        """
        lower_text = text_input.lower()

        # Count keyword hits per crisis type
        hit_counts: dict[str, int] = {
            crisis: sum(1 for kw in kws if kw in lower_text)
            for crisis, kws in CRISIS_KEYWORDS.items()
        }

        best_crisis = max(hit_counts, key=lambda c: hit_counts[c])
        best_hits   = hit_counts[best_crisis]

        if best_hits == 0:
            crisis_type  = "none"
            crisis_score = 0.0
        else:
            crisis_type = best_crisis
            # Cap at 1.0: each keyword hit adds 0.25
            crisis_score = min(best_hits * 0.25, 1.0)

        self.logger.write_trace(
            agent_name="signal_fusion.social",
            step_type="OBSERVE",
            reasoning=(
                f"Social text scanned — best match: '{crisis_type}' "
                f"with {best_hits} keyword hits → score={crisis_score:.2f}"
            ),
            inputs={"text_input": text_input, "hit_counts": hit_counts},
            output={
                "text": text_input,
                "detected_crisis": crisis_type,
                "confidence": crisis_score,
                "keyword_hits": hit_counts,
            },
            confidence_before=0.0,
            confidence_after=crisis_score,
            tool_calls=[],
            duration_ms=2,
        )

        return {
            "text": text_input,
            "detected_crisis": crisis_type,
            "confidence": crisis_score,
            "keyword_hits": hit_counts,
        }

    # ------------------------------------------------------------------
    # Fusion layer
    # ------------------------------------------------------------------
    def fuse(
        self,
        image_result: Optional[dict],
        weather_result: dict,
        social_result: dict,
    ) -> dict:
        """
        Weighted fusion of all three signal sources into a single assessment.

        Image result is optional (endpoint may be called without an image).
        Missing image defaults to 0.0 score so weather + social still work.

        Args:
            image_result   (dict | None): Output from YOLODetector.detect_fire().
            weather_result (dict):        Output from get_weather_signal().
            social_result  (dict):        Output from get_social_signal().

        Returns:
            dict: Fused score, dominant crisis type, and per-source breakdown.
        """
        w_image   = self.sources["image"]["weight"]
        w_weather = self.sources["weather"]["weight"]
        w_social  = self.sources["social"]["weight"]

        # --- Image score -------------------------------------------------
        if image_result and image_result.get("detected"):
            image_score = float(image_result.get("confidence", 0.0))
            image_crisis = "fire"
        elif image_result:
            image_score  = 0.0
            image_crisis = "none"
        else:
            image_score  = 0.0
            image_crisis = "none"

        weather_score  = float(weather_result.get("crisis_score", 0.0))
        weather_crisis = weather_result.get("crisis_type", "none")
        social_score   = float(social_result.get("confidence", 0.0))
        social_crisis  = social_result.get("detected_crisis", "none")

        # Weighted sum
        fused_score: float = (
            image_score   * w_image   +
            weather_score * w_weather +
            social_score  * w_social
        )

        # Vote: pick crisis type with highest weighted contribution
        contributions = {
            "fire":     image_score  * w_image   if image_crisis  == "fire"     else 0.0,
            "flood":    weather_score* w_weather  if weather_crisis == "flood"   else 0.0,
            "heatwave": weather_score* w_weather  if weather_crisis == "heatwave" else 0.0,
        }
        # Add social contributions
        if social_crisis in contributions:
            contributions[social_crisis] += social_score * w_social
        elif social_crisis not in ("none",):
            contributions[social_crisis] = social_score * w_social

        dominant_crisis = max(contributions, key=lambda k: contributions[k])
        if contributions[dominant_crisis] == 0.0:
            dominant_crisis = "none"

        self.logger.write_trace(
            agent_name="signal_fusion.fuse",
            step_type="DECIDE",
            reasoning=(
                f"Fused score={fused_score:.3f} — "
                f"image={image_score:.2f}×{w_image}, "
                f"weather={weather_score:.2f}×{w_weather}, "
                f"social={social_score:.2f}×{w_social} "
                f"→ dominant_crisis='{dominant_crisis}'"
            ),
            inputs={
                "image_score": image_score,
                "weather_score": weather_score,
                "social_score": social_score,
            },
            output={
                "fused_score": fused_score,
                "dominant_crisis": dominant_crisis,
                "contributions": contributions,
            },
            confidence_before=0.5,
            confidence_after=fused_score,
            tool_calls=[],
            duration_ms=1,
        )

        return {
            "fused_score": round(fused_score, 4),
            "dominant_crisis": dominant_crisis,
            "sources": {
                "image":   {"score": image_score,   "crisis": image_crisis},
                "weather": {"score": weather_score, "crisis": weather_crisis},
                "social":  {"score": social_score,  "crisis": social_crisis},
            },
            "contributions": contributions,
        }


    # ------------------------------------------------------------------
    # Convenience aliases (matches user-spec method names)
    # ------------------------------------------------------------------
    def get_weather(self, location: Optional[str] = "default") -> dict:
        """
        Alias for get_weather_signal() matching the public API spec.

        Args:
            location (str, optional): City/area name for the mock data label.

        Returns:
            dict: Weather readings plus boolean risk flags and a crisis_score.
        """
        return self.get_weather_signal(location=location)

    def get_social(self, text: str) -> dict:
        """
        Alias for get_social_signal() matching the public API spec.

        Args:
            text (str): Raw text (social media post, SMS alert, etc.).

        Returns:
            dict: Detected crisis type, keyword hits, and confidence score.
        """
        return self.get_social_signal(text_input=text)


# Module-level singleton for import convenience
signal_fusion = SignalFusion()

